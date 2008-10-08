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

class Pool < ActiveRecord::Base
  acts_as_nested_set

  # moved associations here so that nested set :include directives work
  # TODO: find a way to put this back into vm_resource_pool.rb
  has_many :vms, :dependent => :nullify, :order => "id ASC", :foreign_key => :vm_resource_pool_id
  # TODO: find a way to put this back into hardware_pool.rb
  has_many :hosts, :include => :nics, :dependent => :nullify, :order => "hosts.id ASC", :foreign_key => "hardware_pool_id" do
    def total_cpus
      find(:all).inject(0){ |sum, host| sum + host.num_cpus }
    end
    def total_memory
      find(:all).inject(0){ |sum, host| sum + host.memory }
    end
    def total_memory_in_mb
      find(:all).inject(0){ |sum, host| sum + host.memory_in_mb }
    end
  end

  has_many :storage_pools, :dependent => :nullify, :order => "id ASC", :foreign_key => 'hardware_pool_id' do
    def total_size_in_gb
      find(:all).inject(0){ |sum, sp| sum + sp.storage_volumes.total_size_in_gb }
    end
  end

  has_many :smart_pool_tags, :as => :tagged, :dependent => :destroy
  has_many :smart_pools, :through => :smart_pool_tags

  # used to allow parent traversal before obj is saved to the db
  # (needed for view code 'create' form)
  attr_accessor :tmp_parent

  validates_presence_of :name
  validates_uniqueness_of :name, :scope => :parent_id

  # overloading this method such that we can use permissions.admins to get all the admins for an object
  has_many :permissions, :dependent => :destroy, :order => "id ASC" do
    def super_admins
      find_all_by_user_role(Permission::ROLE_SUPER_ADMIN)
    end
    def admins
      find_all_by_user_role(Permission::ROLE_ADMIN)
    end
    def users
      find_all_by_user_role(Permission::ROLE_USER)
    end
    def monitors
      find_all_by_user_role(Permission::ROLE_MONITOR)
    end
  end

  has_one :quota, :dependent => :destroy

  def create_with_parent(parent, &other_actions)
    transaction do
      save!
      move_to_child_of(parent)
      parent.permissions.each do |permission|
        new_permission = Permission.new({:pool_id     => id,
                                         :uid         => permission.uid,
                                         :user_role   => permission.user_role,
                                         :inherited_from_id =>
                                          permission.inherited_from_id.nil? ?
                                          permission.id :
                                          permission.inherited_from_id})
        new_permission.save!
      end
      yield other_actions if other_actions
    end
  end

  acts_as_xapian :texts => [ :name ],
                 :terms => [ [ :search_users, 'U', "search_users" ] ]

  # this method lists pools with direct permission grants, but by default does
  #  not include implied permissions (i.e. subtrees)
  def self.list_for_user(user, privilege, include_indirect = false)
    if include_indirect
      inherited_clause = ""
    else
      inherited_clause = "and permissions.inherited_from_id is null"
    end
    pools = find(:all, :include => "permissions",
                 :conditions => "permissions.uid='#{user}' #{inherited_clause} and
                       permissions.user_role in
                       ('#{Permission.roles_for_privilege(privilege).join("', '")}')")
  end

  def self.select_hardware_pools(pools)
    pools.select {|pool| pool[:type] == "HardwarePool"}
  end
  def self.select_vm_pools(pools)
    pools.select {|pool| pool[:type] == "VmResourcePool"}
  end
  def self.select_hardware_and_vm_pools(pools)
    pools.select {|pool| ["HardwarePool", "VmResourcePool"].include?(pool[:type])}
  end

  def sub_hardware_pools
    children({:conditions => "type='HardwarePool'"})
  end
  def sub_vm_resource_pools
    children({:conditions => "type='VmResourcePool'"})
  end
  def all_sub_hardware_pools
    all_children({:conditions => "type='HardwarePool'"})
  end
  def all_sub_vm_resource_pools
    all_children({:conditions => "type='VmResourcePool'"})
  end
  def self_and_like_siblings
    self_and_siblings.select {|pool| pool[:type] == self.class.name}
  end

  def named_child(child_name)
    matches = children(:conditions=>"name='#{child_name}'")
    matches ? matches[0] : nil
  end

  def can_view(user)
    has_privilege(user, Permission::PRIV_VIEW)
  end
  def can_control_vms(user)
    has_privilege(user, Permission::PRIV_VM_CONTROL)
  end
  def can_modify(user)
    has_privilege(user, Permission::PRIV_MODIFY)
  end
  def can_view_perms(user)
    has_privilege(user, Permission::PRIV_PERM_VIEW)
  end
  def can_set_perms(user)
    has_privilege(user, Permission::PRIV_PERM_SET)
  end

  def has_privilege(user, privilege)
    permissions.find(:first,
                          :conditions => "permissions.uid='#{user}' and
                         permissions.user_role in
                         ('#{Permission.roles_for_privilege(privilege).join("', '")}')")
  end

  def total_resources
    the_quota = traverse_parents { |pool| pool.quota }
    if the_quota.nil?
      Quota.get_resource_hash(nil, nil, nil, nil, nil)
    else
      the_quota.total_resources
    end
  end

  RESOURCE_LABELS = [["CPUs", :cpus, ""],
                     ["Memory", :memory_in_mb, "(mb)"],
                     ["NICs", :nics, ""],
                     ["VMs", :vms, ""],
                     ["Disk", :storage_in_gb, "(gb)"]]

  #needed by tree widget for display
  def hasChildren
    return (rgt - lft) != 1
  end

  def self.nav_json(pools, open_list, filter_vm_pools=false)
    pool_hash(pools, open_list, filter_vm_pools).to_json
  end
  def self.pool_hash(pools, open_list, filter_vm_pools=false)
    pools.collect do |pool|
      hash = pool.json_hash_element
      pool_children = nil
      if filter_vm_pools
        pool_children = pool.sub_hardware_pools
        hash[:hasChildren] = !pool_children.empty?
      else
        hash[:hasChildren] = pool.hasChildren
      end
      found = false
      open_list.each do |open_pool|
        if pool.id == open_pool.id
          new_open_list = open_list[(open_list.index(open_pool)+1)..-1]
          unless new_open_list.empty?
            pool_children = pool.children unless pool_children
            hash[:children] = pool_hash(pool_children, new_open_list, filter_vm_pools)
            hash[:expanded] = true
            hash.delete(:hasChildren)
          end
          break
        end
      end
      hash
    end
  end

  def json_hash_element
    { :id => id, :type => self[:type], :text => name, :name => name, :parent_id => parent_id}
  end

  def hash_element
    { :id => id, :obj => self}
  end

  def minimal_hash_element
    { :id => id}
  end

  # if opts specifies order, this will be removed, since this impl
  # relies on full_set's ordering
  # in additon to standard find opts, add :method to the hash to specify
  # an alternative set of attributes (such as json_hash_element, etc.)
  # or :current_id to specify which pool gets ":selected => true" set
  def full_set_nested(opts={})
    method = opts.delete(:method) {:hash_element}
    privilege = opts.delete(:privilege)
    user = opts.delete(:user)
    smart_pool_set = opts.delete(:smart_pool_set)
    if privilege and user
      opts[:include] = "permissions"
      opts[:conditions] = "permissions.uid='#{user}' and
                       permissions.user_role in
                       ('#{Permission.roles_for_privilege(privilege).join("', '")}')"
    end
    current_id = opts.delete(:current_id)
    opts.delete(:order)
    subtree_list = full_set(opts)
    subtree_list -= [self] if smart_pool_set
    return_tree_list = []
    ref_hash = {}
    subtree_list.each do |pool|
      new_element = pool.send(method)
      ref_hash[pool.id] = new_element
      parent = ref_hash[pool.parent_id]
      if parent
        parent[:children] ||= []
        parent[:children] << new_element
      else
        # for smart pools include the parent DirectoryPool
        if smart_pool_set and pool[:type]=="SmartPool"
          pool_parent = pool.parent
          parent_element = pool_parent.send(method)
          ref_hash[pool_parent.id] = parent_element
          return_tree_list << parent_element
          parent_element[:children] ||= []
          parent_element[:children] << new_element
        else
          return_tree_list << new_element
        end
      end
    end
    ref_hash[current_id][:selected] = true if current_id
    return_tree_list
  end

  def self.call_finder(*args)
    obj = args.shift
    method = args.shift
    obj.send(method, *args)
  end

  def display_name
    name
  end
  def display_class
    get_type_label
  end

  def search_users
    permissions.collect {|perm| perm.uid}
  end

  def self.find_by_path(path)
    segs = path.split("/")
    unless segs.shift.empty?
      raise "Path must be absolute, but is #{path}"
    end
    default_pool = DirectoryPool.get_directory_root
    if segs.shift == default_pool.name
      segs.inject(default_pool) do |pool, seg|
        pool.children.find { |p| p.name == seg } if pool
      end
    end
  end

  def class_and_id
    self.class.name + "_" + self.id.to_s
  end
  protected
  def traverse_parents
    if id
      ancestor_array = self_and_ancestors
    elsif tmp_parent
      ancestor_array = tmp_parent.self_and_ancestors
    else
      ancestor_array = []
    end
    ancestor_array.reverse_each do |the_pool|
      val = yield the_pool
      return val if val
    end
    return nil
  end


end
