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

class CreateTasks < ActiveRecord::Migration
  def self.up
    create_table :tasks do |t|
      t.string    :user
      t.string    :type
      t.string    :action
      t.string    :state
      t.string    :args
      t.timestamp :created_at
      t.timestamp :time_started
      t.timestamp :time_ended
      t.text      :message
      t.integer   :lock_version, :default => 0

      # VmTask columns
      t.integer   :vm_id
      t.foreign_key :vms, :name => 'fk_tasks_vms'

      # StorageTask columns
      t.integer   :storage_pool_id
      t.foreign_key :storage_pools, :name => 'fk_tasks_pools'

      # HostTask columns
      t.integer   :host_id
      t.foreign_key :hosts, :name => 'fk_tasks_hosts'
    end
  end

  def self.down
    drop_table :tasks
  end
end
