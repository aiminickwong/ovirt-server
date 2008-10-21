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

  acts_as_xapian :texts => [ :ip_addr, :target, :export_path, :type ],
                 :terms => [ [ :search_users, 'U', "search_users" ] ]
  ISCSI = "iSCSI"
  NFS   = "NFS"
  LVM   = "LVM"
  STORAGE_TYPES = { ISCSI => "Iscsi",
                    NFS   => "Nfs",
                    LVM   => "Lvm" }
  STORAGE_TYPE_PICKLIST = STORAGE_TYPES.keys - [LVM]

  def self.factory(type, params = nil)
    case type
    when ISCSI
      return IscsiStoragePool.new(params)
    when NFS
      return NfsStoragePool.new(params)
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

  def storage_tree_element(vm_to_include=nil)
    return_hash = { :id => id,
      :type => self[:type],
      :text => display_name,
      :name => display_name,
      :available => false,
      :create_volume => user_subdividable,
      :selected => false}
    condition = "vms.id is null"
    if (vm_to_include and vm_to_include.id)
      condition +=" or vms.id=#{vm_to_include.id}"
    end
    return_hash[:children] = storage_volumes.find(:all,
                               :include => :vms,
                               :conditions => condition).collect do |volume|
      volume.storage_tree_element(vm_to_include)
    end
    return_hash
  end
end
