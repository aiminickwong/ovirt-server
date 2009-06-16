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

require File.dirname(__FILE__) + '/../test_helper'
require 'task_controller'

# Re-raise errors caught by the controller.
class TaskController; def rescue_action(e) raise e end; end

class TaskControllerTest < ActionController::TestCase
  fixtures :tasks, :vms, :pools

  def setup
    @controller = TaskController.new
    @request    = ActionController::TestRequest.new
    @response   = ActionController::TestResponse.new

    @task_id = tasks(:shutdown_production_httpd_appliance_task).id
  end

  def test_show
    get :show, :id => @task_id

    assert_response :success
    assert_template 'show'

    assert_not_nil assigns(:task)
    assert assigns(:task).valid?
  end

end
