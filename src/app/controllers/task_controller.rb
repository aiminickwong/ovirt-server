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

class TaskController < ApplicationController
  def show
    @task = Task.find(params[:id])
    if @task[:type] == VmTask.name
      set_perms(@task.vm.vm_resource_pool)
    elsif @task[:type] == StorageTask.name 
      set_perms(@task.storage_pool.hardware_pool)
    elsif @task[:type] == StorageVolumeTask.name
      set_perms(@task.storage_volume.storage_pool.hardware_pool)
    elsif @task[:type] == HostTask.name 
      set_perms(@task.host.hardware_pool)
    end
    unless @can_view
      flash[:notice] = 'You do not have permission to view this task: redirecting to top level'
      redirect_to :controller => 'dashboard'
    end

  end

end
