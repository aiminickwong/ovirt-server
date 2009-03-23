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

class HostTask < Task

  ACTION_CLEAR_VMS = "clear_vms"

  def after_initialize
    self.hardware_pool = task_target.hardware_pool if self.task_target_type=="Host"
  end

  def task_obj
    if self.host
      "Host;;;#{self.host.id};;;#{self.host.hostname}"
    else
      ""
    end
  end

  def vm
    nil
  end
  def storage_volume
    nil
  end
  def storage_pool
    nil
  end
end
