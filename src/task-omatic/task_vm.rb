# Copyright (C) 2008 Red Hat, Inc.
# Written by Chris Lalancette <clalance@redhat.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA  02110-1301, USA.  A copy of the GNU General Public License is
# also available at http://www.gnu.org/copyleft/gpl.html.

require 'rexml/document'
include REXML

require 'utils'

gem 'cobbler'
require 'cobbler'

def findHostSLA(vm)
  host = nil

  vm.vm_resource_pool.get_hardware_pool.hosts.each do |curr|
    # FIXME: we probably need to add in some notion of "load" into this check
    if curr.num_cpus >= vm.num_vcpus_allocated \
      and curr.memory >= vm.memory_allocated \
      and not curr.is_disabled.nil? and curr.is_disabled == 0 \
      and curr.state == Host::STATE_AVAILABLE \
      and (vm.host_id.nil? or (not vm.host_id.nil? and vm.host_id != curr.id))
      host = curr
      break
    end
  end

  if host == nil
    # we couldn't find a host that matches this criteria
    raise "No host matching VM parameters could be found"
  end

  return host
end

def findHost(host_id)
  host = Host.find(:first, :conditions => [ "id = ?", host_id])

  if host == nil
    # Hm, we didn't find the host_id.  Seems odd.  Return a failure
    raise "Could not find host_id " + host_id.to_s
  end

  return host
end

def connect_storage_pools(conn, storage_volumes)
  storagedevs = []
  storage_volumes.each do |volume|
    # here, we need to iterate through each volume and possibly attach it
    # to the host we are going to be using
    db_pool = volume.storage_pool
    if db_pool == nil
      # Hum.  Specified by the VM description, but not in the storage pool?
      # continue on and hope for the best
      puts "Couldn't find pool for volume #{volume.path}; skipping"
      next
    end

    # we have to special case LVM pools.  In that case, we need to first
    # activate the underlying physical device, and then do the logical one
    if volume[:type] == "LvmStorageVolume"
      phys_libvirt_pool = get_libvirt_pool_from_volume(volume)
      phys_libvirt_pool.connect(conn)
    end

    libvirt_pool = LibvirtPool.factory(db_pool)
    libvirt_pool.connect(conn)

    # OK, the pool should be all set.  The last thing we need to do is get
    # the path based on the volume name
    storagedevs << libvirt_pool.lookup_vol_by_name(volume.read_attribute(volume.volume_name)).path
  end

  return storagedevs
end

def remove_pools(conn, type = nil)
  all_storage_pools(conn).each do |remote_pool_name|
    pool = conn.lookup_storage_pool_by_name(remote_pool_name)

    if type == nil or type == Document.new(pool.xml_desc).root.attributes['type']
      begin
        pool.destroy
      rescue
      end

      begin
        # if the destroy failed, we still try to undefine; it may be a pool
        # that was previously destroyed but not undefined for whatever reason
        pool.undefine
      rescue
        # do nothing if any of this failed; the worst that happens is that
        # we leave a pool configured
        puts "Could not teardown pool " + remote_pool_name + "; skipping"
      end
    end
  end
end

def teardown_storage_pools(conn)
  # FIXME: this needs to get a *lot* smarter.  In particular, we want to make
  # sure we can tear down unused pools even when there are other guests running
  if conn.list_domains.empty?
    # OK, there are no running guests on this host anymore.  We can teardown
    # any storage pools that are there without fear

    # we first have to tear-down LVM pools, because they might depend on the
    # underlying physical pools
    remove_pools(conn, "logical")

    # now tear down the rest of the pools
    remove_pools(conn)
  end
end

def create_vm_xml(name, uuid, memAllocated, memUsed, vcpus, bootDevice,
                  macAddr, bridge, diskDevices)
  doc = Document.new

  doc.add_element("domain", {"type" => "kvm"})

  doc.root.add_element("name").add_text(name)

  doc.root.add_element("uuid").add_text(uuid)

  doc.root.add_element("memory").add_text(memAllocated.to_s)

  doc.root.add_element("currentMemory").add_text(memUsed.to_s)

  doc.root.add_element("vcpu").add_text(vcpus.to_s)

  doc.root.add_element("os")
  doc.root.elements["os"].add_element("type").add_text("hvm")
  doc.root.elements["os"].add_element("boot", {"dev" => bootDevice})

  doc.root.add_element("clock", {"offset" => "utc"})

  doc.root.add_element("on_poweroff").add_text("destroy")

  doc.root.add_element("on_reboot").add_text("restart")

  doc.root.add_element("on_crash").add_text("destroy")

  doc.root.add_element("devices")
  doc.root.elements["devices"].add_element("emulator").add_text("/usr/bin/qemu-kvm")

  devs = ['hda', 'hdb', 'hdc', 'hdd']
  which_device = 0
  diskDevices.each do |disk|
    is_cdrom = (disk =~ /\.iso/) ? true : false

    diskdev = Element.new("disk")
    diskdev.add_attribute("type", is_cdrom ? "file" : "block")
    diskdev.add_attribute("device", is_cdrom ? "cdrom" : "disk")

    if is_cdrom
      diskdev.add_element("readonly")
      diskdev.add_element("source", {"file" => disk})
      diskdev.add_element("target", {"dev" => devs[which_device], "bus" => "ide"})
    else
      diskdev.add_element("source", {"dev" => disk})
      diskdev.add_element("target", {"dev" => devs[which_device]})
    end

    doc.root.elements["devices"] << diskdev
    which_device += 1
  end

  doc.root.elements["devices"].add_element("interface", {"type" => "bridge"})
  doc.root.elements["devices"].elements["interface"].add_element("mac", {"address" => macAddr})
  doc.root.elements["devices"].elements["interface"].add_element("source", {"bridge" => bridge})
  doc.root.elements["devices"].add_element("input", {"type" => "mouse", "bus" => "ps2"})
  doc.root.elements["devices"].add_element("graphics", {"type" => "vnc", "port" => "-1", "listen" => "0.0.0.0"})

  serial = Element.new("serial")
  serial.add_attribute("type", "pty")
  serial.add_element("target", {"port" => "0"})
  doc.root.elements["devices"] << serial

  return doc
end

def setVmState(vm, state)
  vm.state = state
  vm.save!
end

def setVmVncPort(vm, domain)
  doc = REXML::Document.new(domain.xml_desc)
  attrib = REXML::XPath.match(doc, "//graphics/@port")
  if not attrib.empty?:
    vm.vnc_port = attrib.to_s.to_i
  end
  vm.save!
end

def findVM(task, fail_on_nil_host_id = true)
  # find the matching VM in the vms table
  vm = task.vm

  if vm == nil
    raise "VM not found for task " + task.id
  end

  if vm.host_id == nil && fail_on_nil_host_id
    # in this case, we have no idea where the VM is.  How can we handle this
    # gracefully?  We don't necessarily want to just set the VM state to off;
    # if the machine does happen to be running somewhere and we set it to
    # disabled here, and then start it again, we could corrupt the disk

    # FIXME: the right thing to do here is probably to contact all of the
    # hosts we know about and ensure that the domain isn't running; then we
    # can mark it either as off (if we didn't find it), or mark the correct
    # vm.host_id if we did.  However, if you have a large number of hosts
    # out there, this could take a while.
    raise "No host_id for VM " + vm.id.to_s
  end

  return vm
end

def setVmShutdown(vm)
  vm.host_id = nil
  vm.memory_used = nil
  vm.num_vcpus_used = nil
  vm.state = Vm::STATE_STOPPED
  vm.needs_restart = nil
  vm.vnc_port = nil
  vm.save!
end

def create_vm(task)
  puts "create_vm"

  vm = findVM(task, false)

  if vm.state != Vm::STATE_PENDING
    raise "VM not pending"
  end
  setVmState(vm, Vm::STATE_CREATING)

  # create cobbler system profile
  begin
    # FIXME: Presently the wui handles all cobbler system creation.
    # This should be moved out of the wui into Taskomatic.  Specifically
    # here, and in the edit_vm methods.

    setVmState(vm, Vm::STATE_STOPPED)
  rescue Exception => error
    setVmState(vm, Vm::STATE_CREATE_FAILED)
    raise "Unable to create system: #{error.message}"
  end
end

def shutdown_vm(task)
  puts "shutdown_vm"

  # here, we are given an id for a VM to shutdown; we have to lookup which
  # physical host it is running on

  vm = findVM(task)

  if vm.state == Vm::STATE_STOPPED
    # the VM is already shutdown; just return success
    setVmShutdown(vm)
    return
  elsif vm.state == Vm::STATE_SUSPENDED
    raise "Cannot shutdown suspended domain"
  elsif vm.state == Vm::STATE_SAVED
    raise "Cannot shutdown saved domain"
  end

  vm_orig_state = vm.state
  setVmState(vm, Vm::STATE_STOPPING)

  begin
    conn = Libvirt::open("qemu+tcp://" + vm.host.hostname + "/system")
    dom = conn.lookup_domain_by_uuid(vm.uuid)
    # FIXME: crappy.  Right now we destroy the domain to make sure it
    # really went away.  We really want to shutdown the domain to make
    # sure it gets a chance to cleanly go down, but how can we tell when
    # it is truly shut off?  And then we probably need a timeout in case
    # of problems.  Needs more thought
    #dom.shutdown
    dom.destroy

    begin
      dom.undefine
    rescue
      # undefine can fail, for instance, if we live migrated from A -> B, and
      # then we are shutting down the VM on B (because it only has "transient"
      # XML).  Therefore, just ignore undefine errors so we do the rest
      # FIXME: we really should have a marker in the database somehow so that
      # we can tell if this domain was migrated; that way, we can tell the
      # difference between a real undefine failure and one because of migration
    end

    teardown_storage_pools(conn)

    conn.close
  rescue => ex
    setVmState(vm, vm_orig_state)
    raise ex
  end

  setVmShutdown(vm)
end

def start_vm(task)
  puts "start_vm"

  # here, we are given an id for a VM to start

  vm = findVM(task, false)

  if vm.state == Vm::STATE_RUNNING
    # the VM is already running; just return success
    return
  elsif vm.state == Vm::STATE_SUSPENDED
    raise "Cannot start suspended domain"
  elsif vm.state == Vm::STATE_SAVED
    raise "Cannot start saved domain"
  end

  # FIXME: Validate that the VM is still within quota

  vm_orig_state = vm.state
  setVmState(vm, Vm::STATE_STARTING)

  begin
    if vm.host_id != nil
      # OK, marked in the database as already running on a host; for now, we
      # will just fail the operation

      # FIXME: we probably want to go out to the host it is marked on and check
      # things out, just to make sure things are consistent
      raise "VM already running"
    end

    # OK, now that we found the VM, go looking in the hardware_pool
    # hosts to see if there is a host that will fit these constraints
    host = findHostSLA(vm)

    # if we're booting from a CDROM the VM is an image,
    # then we need to add the NFS mount as a storage volume for this
    # boot
    #
    if (vm.boot_device == Vm::BOOT_DEV_CDROM) && vm.uses_cobbler? && (vm.cobbler_type == Vm::IMAGE_PREFIX)
      details = Cobbler::Image.find_one(vm.cobbler_name)

      raise "Image #{vm.cobbler_name} not found in Cobbler server" unless details

      ignored, ip_addr, export_path, filename =
        details.file.split(/(.*):(.*)\/(.*)/)

      found = false

      vm.storage_volumes.each do |volume|
        if volume.filename == filename
          if (volume.storage_pool.ip_addr == ip_addr) &&
          (volume.storage_pool.export_path == export_path)
            found = true
          end
        end
      end

      unless found
        # Create a new transient NFS storage volume
        # This volume is *not* persisted.
        image_volume = StorageVolume.factory("NFS",
          :filename => filename
        )

        image_volume.storage_pool
        image_pool = StoragePool.factory(StoragePool::NFS)

        image_pool.ip_addr = ip_addr
        image_pool.export_path = export_path
        image_pool.storage_volumes << image_volume
        image_volume.storage_pool = image_pool
      end
    end

    conn = Libvirt::open("qemu+tcp://" + host.hostname + "/system")

    volumes = []
    volumes += vm.storage_volumes
    volumes << image_volume if image_volume
    storagedevs = connect_storage_pools(conn, volumes)

    # FIXME: get rid of the hardcoded bridge
    xml = create_vm_xml(vm.description, vm.uuid, vm.memory_allocated,
                        vm.memory_used, vm.num_vcpus_allocated, vm.boot_device,
                        vm.vnic_mac_addr, "ovirtbr0", storagedevs)

    dom = conn.define_domain_xml(xml.to_s)
    dom.create

    setVmVncPort(vm, dom)

    conn.close
  rescue => ex
    setVmState(vm, vm_orig_state)
    raise ex
  end

  vm.host_id = host.id
  vm.state = Vm::STATE_RUNNING
  vm.memory_used = vm.memory_allocated
  vm.num_vcpus_used = vm.num_vcpus_allocated
  vm.boot_device = Vm::BOOT_DEV_HD
  vm.save!
end

def save_vm(task)
  puts "save_vm"

  # here, we are given an id for a VM to suspend

  vm = findVM(task)

  if vm.state == Vm::STATE_SAVED
    # the VM is already saved; just return success
    return
  elsif vm.state == Vm::STATE_SUSPENDED
    raise "Cannot save suspended domain"
  elsif vm.state == Vm::STATE_STOPPED
    raise "Cannot save shutdown domain"
  end

  vm_orig_state = vm.state
  setVmState(vm, Vm::STATE_SAVING)

  begin
    conn = Libvirt::open("qemu+tcp://" + vm.host.hostname + "/system")
    dom = conn.lookup_domain_by_uuid(vm.uuid)
    dom.save("/tmp/" + vm.uuid + ".save")
    conn.close
  rescue => ex
    setVmState(vm, vm_orig_state)
    raise ex
  end

  # note that we do *not* reset the host_id here, since we stored the saved
  # vm state information locally.  restore_vm will pick it up from here

  # FIXME: it would be much nicer to be able to save the VM and remove the
  # the host_id and undefine the XML; that way we could resume it on another
  # host later.  This can be done once we have the storage APIs, but it will
  # need more work

  setVmState(vm, Vm::STATE_SAVED)
end

def restore_vm(task)
  puts "restore_vm"

  # here, we are given an id for a VM to start

  vm = findVM(task)

  if vm.state == Vm::STATE_RUNNING
    # the VM is already saved; just return success
    return
  elsif vm.state == Vm::STATE_SUSPENDED
    raise "Cannot restore suspended domain"
  elsif vm.state == Vm::STATE_STOPPED
    raise "Cannot restore shutdown domain"
  end

  vm_orig_state = vm.state
  setVmState(vm, Vm::STATE_RESTORING)

  begin
    # FIXME: we should probably go out to the host and check what it thinks
    # the state is

    conn = Libvirt::open("qemu+tcp://" + vm.host.hostname + "/system")
    dom = conn.lookup_domain_by_uuid(vm.uuid)
    dom.restore

    setVmVncPort(vm, dom)

    conn.close
  rescue => ex
    setVmState(vm, vm_orig_state)
    raise ex
  end

  setVmState(vm, Vm::STATE_RUNNING)
end

def suspend_vm(task)
  puts "suspend_vm"

  # here, we are given an id for a VM to suspend; we have to lookup which
  # physical host it is running on

  vm = findVM(task)

  if vm.state == Vm::STATE_SUSPENDED
    # the VM is already suspended; just return success
    return
  elsif vm.state == Vm::STATE_STOPPED
    raise "Cannot suspend stopped domain"
  elsif vm.state == Vm::STATE_SAVED
    raise "Cannot suspend saved domain"
  end

  vm_orig_state = vm.state
  setVmState(vm, Vm::STATE_SUSPENDING)

  begin
    conn = Libvirt::open("qemu+tcp://" + vm.host.hostname + "/system")
    dom = conn.lookup_domain_by_uuid(vm.uuid)
    dom.suspend
    conn.close
  rescue => ex
    setVmState(vm, vm_orig_state)
    raise ex
  end

  # note that we do *not* reset the host_id here, since we just suspended the VM
  # resume_vm will pick it up from here

  setVmState(vm, Vm::STATE_SUSPENDED)
end

def resume_vm(task)
  puts "resume_vm"

  # here, we are given an id for a VM to start

  vm = findVM(task)

  # OK, marked in the database as already running on a host; let's check it

  if vm.state == Vm::STATE_RUNNING
    # the VM is already suspended; just return success
    return
  elsif vm.state == Vm::STATE_STOPPED
    raise "Cannot resume stopped domain"
  elsif vm.state == Vm::STATE_SAVED
    raise "Cannot resume suspended domain"
  end

  vm_orig_state = vm.state
  setVmState(vm, Vm::STATE_RESUMING)

  begin
    conn = Libvirt::open("qemu+tcp://" + vm.host.hostname + "/system")
    dom = conn.lookup_domain_by_uuid(vm.uuid)
    dom.resume
    conn.close
  rescue => ex
    setVmState(vm, vm_orig_state)
    raise ex
  end

  setVmState(vm, Vm::STATE_RUNNING)
end

def update_state_vm(task)
  puts "update_state_vm"

  # NOTE: findVM() will only return a vm if all the host information is filled
  # in.  So if a vm that we thought was stopped is running, this returns nil
  # and we don't update any information about it.  The tricky part
  # is that we're still not sure what to do in this case :).  - Ian
  #
  # Actually for migration it is necessary that it be able to update
  # the host and state of the VM once it is migrated.
  vm = findVM(task, false)
  new_vm_state, host_id_str = task.args.split(",")
  if (vm.host_id == nil) and host_id_str
    vm.host_id = host_id_str.to_i
  end


  vm_effective_state = Vm::EFFECTIVE_STATE[vm.state]
  task_effective_state = Vm::EFFECTIVE_STATE[new_vm_state]

  if vm_effective_state != task_effective_state
    vm.state = new_vm_state

    if task_effective_state == Vm::STATE_STOPPED
      setVmShutdown(vm)
    end
    vm.save!
    puts "Updated state to " + new_vm_state
  end
end

def migrate(vm, dest = nil)
  if vm.state == Vm::STATE_STOPPED
    raise "Cannot migrate stopped domain"
  elsif vm.state == Vm::STATE_SUSPENDED
    raise "Cannot migrate suspended domain"
  elsif vm.state == Vm::STATE_SAVED
    raise "Cannot migrate saved domain"
  end

  vm_orig_state = vm.state
  setVmState(vm, Vm::STATE_MIGRATING)

  begin
    src_host = findHost(vm.host_id)
    unless dest.nil? or dest.empty?
      if dest.to_i == vm.host_id
        raise "Cannot migrate from host " + src_host.hostname + " to itself!"
      end
      dst_host = findHost(dest.to_i)
    else
      dst_host = findHostSLA(vm)
    end

    src_conn = Libvirt::open("qemu+tcp://" + src_host.hostname + "/system")
    dst_conn = Libvirt::open("qemu+tcp://" + dst_host.hostname + "/system")

    connect_storage_pools(dst_conn, vm)

    dom = src_conn.lookup_domain_by_uuid(vm.uuid)
    dom.migrate(dst_conn, Libvirt::Domain::MIGRATE_LIVE)

    # if we didn't raise an exception, then the migration was successful.  We
    # still have a pointer to the now-shutdown domain on the source side, so
    # undefine it
    begin
      dom.undefine
    rescue
      # undefine can fail, for instance, if we live migrated from A -> B, and
      # then we are shutting down the VM on B (because it only has "transient"
      # XML).  Therefore, just ignore undefine errors so we do the rest
      # FIXME: we really should have a marker in the database somehow so that
      # we can tell if this domain was migrated; that way, we can tell the
      # difference between a real undefine failure and one because of migration
    end

    teardown_storage_pools(src_conn)
    dst_conn.close
    src_conn.close
  rescue => ex
    # FIXME: ug.  We may have open connections that we need to close; not
    # sure how to handle that
    setVmState(vm, vm_orig_state)
    raise ex
  end

  setVmState(vm, Vm::STATE_RUNNING)
  vm.host_id = dst_host.id
  vm.save!
end

def migrate_vm(task)
  puts "migrate_vm"

  # here, we are given an id for a VM to migrate; we have to lookup which
  # physical host it is running on

  vm = findVM(task)

  migrate(vm, task.args)
end
