#
# Copyright (C) 2008 Red Hat, Inc.
# Written by Scott Seago <sseago@redhat.com>
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

class StoragePool < ActiveRecord::Base
  belongs_to              :hardware_pool
  has_many :tasks, :as => :task_target, :dependent => :destroy, :order => "id ASC" do
    def queued
      find(:all, :conditions=>{:state=>Task::STATE_QUEUED})
    end
  end
  has_many                :storage_volumes, :dependent => :destroy, :include => :storage_pool do
    def total_size_in_gb
      find(:all).inject(0){ |sum, sv| sum + sv.size_in_gb }
    end
    def full_vm_list
      find(:all).inject([]){ |list, sv| list + sv.vms }
    end
  end

  has_many :smart_pool_tags, :as => :tagged, :dependent => :destroy
  has_many :smart_pools, :through => :smart_pool_tags


  validates_presence_of :hardware_pool_id

  validates_inclusion_of :type,
    :in => %w( IscsiStoragePool LvmStoragePool NfsStoragePool GlusterfsStoragePool )


  validates_numericality_of :capacity,
     :greater_than_or_equal_to => 0,
     :unless => Proc.new { |storage_pool| storage_pool.capacity.nil? }

  acts_as_xapian :texts => [ :ip_addr, :target, :export_path, :type ],
                 :terms => [ [ :search_users, 'U', "search_users" ] ],
                 :eager_load => :smart_pools
  ISCSI = "iSCSI"
  NFS   = "NFS"
  GLUSTERFS = "GLUSTERFS"
  LVM   = "LVM"
  STORAGE_TYPES = { ISCSI => "Iscsi",
                    NFS   => "Nfs",
                    GLUSTERFS => "Glusterfs",
                    LVM   => "Lvm" }
  STORAGE_TYPE_PICKLIST = STORAGE_TYPES.keys - [LVM]

  STATE_PENDING_SETUP    = "pending_setup"
  STATE_PENDING_DELETION = "pending_deletion"
  STATE_AVAILABLE        = "available"

  validates_inclusion_of :state,
    :in => [ STATE_PENDING_SETUP, STATE_PENDING_DELETION, STATE_AVAILABLE]

  def self.factory(type, params = {})
    params[:state] = STATE_PENDING_SETUP unless params[:state]
    case type
    when ISCSI
      return IscsiStoragePool.new(params)
    when NFS
      return NfsStoragePool.new(params)
    when GLUSTERFS
      return GlusterfsStoragePool.new(params)
    when LVM
      return LvmStoragePool.new(params)
    else
      return nil
    end
  end

  def display_name
    "#{get_type_label}: #{ip_addr}:#{label_components}"
  end

  def get_type_label
    STORAGE_TYPES.invert[self.class.name.gsub("StoragePool", "")]
  end
  def display_class
    "Storage Pool"
  end

  def search_users
    hardware_pool.search_users
  end

  def user_subdividable
    false
  end

  #--
  #TODO: the following two methods should be moved out somewhere, perhaps an 'acts_as' plugin?
  #Though ui_parent will have class specific impl
  #++
  #This is a convenience method for use in the ui to simplify creating a unigue id for placement/retrieval
  #in/from the DOM.  This was added because there is a chance of duplicate ids between different object types,
  #and multiple object type will appear concurrently in the ui.  The combination of type and id should be unique.
  def ui_object
    self.class.to_s + '_' + id.to_s
  end

  #This is a convenience method for use in the processing and manipulation of json in the ui.
  #This serves as a key both for determining where to attached elements in the DOM and quickly
  #accessing and updating a cached object on the client.
  def ui_parent
    nil
  end

  def storage_tree_element(params = {})
    vm_to_include=params.fetch(:vm_to_include, nil)
    filter_unavailable = params.fetch(:filter_unavailable, true)
    include_used = params.fetch(:include_used, false)
    state = params.fetch(:state,nil)
    return_hash = { :id => id,
      :type => self[:type],
      :name => display_name,
      :ui_object => ui_object,
      :state => state,
      :available => false,
      :create_volume => user_subdividable,
      :ui_parent => ui_parent,
      :selected => false,
      :is_pool => true}
    conditions = nil
    unless include_used
      conditions = "vms.id is null"
      if (vm_to_include and vm_to_include.id)
        conditions +=" or vms.id=#{vm_to_include.id}"
      end
    end
    if filter_unavailable
      availability_conditions = "(storage_volumes.state = '#{StoragePool::STATE_AVAILABLE}'
        or storage_volumes.state = '#{StoragePool::STATE_PENDING_SETUP}')"
      if conditions.nil?
        conditions = availability_conditions
      else
        conditions ="(#{conditions}) and (#{availability_conditions})"
      end
    end
    return_hash[:children] = storage_volumes.find(:all,
                               :include => :vms,
                               :conditions => conditions).collect do |volume|
      volume.storage_tree_element(params)
    end
    return_hash
  end

  def permission_obj
    hardware_pool
  end

  def movable?
    storage_volumes.each{ |x|
       return false unless x.movable?
    }
    return true
  end

  def not_movable_reason
    return "Storage in use"
  end
end
