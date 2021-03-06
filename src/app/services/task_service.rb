#
# Copyright (C) 2009 Red Hat, Inc.
# Written by Scott Seago <sseago@redhat.com>,
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
# Mid-level API: Business logic around tasks
module TaskService
  include ApplicationService

  # Load the Task with +id+ for viewing
  #
  # === Instance variables
  # [<tt>@task</tt>] stores the Task with +id+
  # === Required permissions
  # [<tt>Privilege::VIEW</tt>] on task target's Pool
  def svc_show(id)
    lookup(id,Privilege::VIEW)
  end

  # Cancel the the Task with +id+
  #
  # === Instance variables
  # [<tt>@task</tt>] stores the Task with +id+
  # === Required permissions
  # [<tt>Privilege::MODIFY</tt>] on task target's Pool
  def svc_cancel(id)
    lookup(id,Privilege::MODIFY)
    unless @task.state == Task::STATE_QUEUED
      raise ActionError.new("Task state is #{@task.state} instead of queued.")
    end
    @task.cancel
  end

  private
  def lookup(id, priv)
    @task = Task.find(id)
    authorized!(priv,@task.task_target.permission_obj)
  end

end
