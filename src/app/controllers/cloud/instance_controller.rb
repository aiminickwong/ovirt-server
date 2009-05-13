#
# Copyright (C) 2009 Red Hat, Inc.
# Written by Jason Guiditta <jguiditt@redhat.com>
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


class Cloud::InstanceController < Cloud::CloudController

  before_filter :handle_form

  def index
    list
  end

  def list
    page = find_in_params_or_default(:page, 1)
    order = find_in_params_or_default(:sort,"vms.id")
    @vms = Vm.paged_with_perms(@user,
                            Privilege::VIEW,
                            # NOTE: maybe this ^^ part could be taken care of behind the scenes?
                            # Also, needs to be changed to a cloud priv
                            page, order)
    @actions = VmTask.get_vm_actions
    show
  end

  def show
    ids = params[:ids]
    task_page = find_in_params_or_default(:task_page, 1)
    task_order = find_in_params_or_default(:task_order, "tasks.id")
    @vm_details = Vm.find(ids) if ids
    if @vm_details
      @tasks = VmTask.paginate(:conditions => ["task_target_id in (:ids)",{:ids => ids}],
                             :per_page => 5, :page => task_page, :order => task_order)
    end
  end

  # TODO: implement
  def create
  end

  # TODO: implement
  def update
  end

  # TODO: implement
  def destroy
  end

  # TODO: implement
  def new
  end

  # TODO: implement
  def edit
  end

  private

# Pass in the symbol for the param key you want, and an optional default value
  def find_in_params_or_default(key, default=nil)
    return params[key] && params[key] != "" ? params[key] : default
  end

# This redirects the user to a get url if they are just trying to view details for one or more
# instances.
# TODO: if the user is trying to submit an acton on selected instances, call the service
# layer and display the :flash (might still want to do :get redirect to keep pagination/sorting
# correct.
  def handle_form
    case params[:submit_for_list]
      when "Show Selected"
        params.delete(:submit_for_list)
        redirect_to :action => "index", :params => params
        return
#    Do this if we have submitted an action on one or more vms.
#    svc_vm_action(params[:ids], params[:vm_action], params[:action_args])
    end
  end

end
