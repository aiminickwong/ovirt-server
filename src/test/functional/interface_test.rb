#
# Copyright (C) 2008 Red Hat, Inc.
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

if File.exists? File.dirname(__FILE__) + '/../selenium.rb'
 require 'yaml'

 require File.dirname(__FILE__) + '/../test_helper'
 require File.dirname(__FILE__) + '/../selenium'

 class InterfaceTest < Test::Unit::TestCase
     def setup
        @config = YAML::load(File.open("#{RAILS_ROOT}/config/selenium.yml"))
        @site_url = "http://"+
                    @config["ovirt_server"]["address"] + "/ovirt/"

        @browser = Selenium::SeleniumDriver.new(
                        @config["selenium_server"]["address"],
                        @config["selenium_server"]["port"],
                        @config["selenium_server"]["browser"],
                        @site_url,
		          15000)
        @browser.start
        @browser.set_speed(50) # ms delay between operations
        @browser.open(@site_url)
     end

     def teardown
        @browser.close
        @browser.stop
     end

     def test_1_ovirt
        assert_equal("Dashboard", @browser.get_title())
     end

     def test_2_view_pool
      @browser.open("http://192.168.50.2/ovirt/")
      @browser.wait_for_condition(
            "selenium.isElementPresent(\"//ul[@id='nav_tree']/li/div\")",
            10000)
      @browser.click(
            "//ul[@id='nav_tree']/li/div")  # click 'default pool' link
      @browser.wait_for_condition(
           "selenium.isElementPresent(\"//div[@class='summary_title']\")",
            50000)

      # verify the title of the pool
      assert_equal("default",
                  @browser.get_text("//div[@class='summary_title']"))
     end

     def test_3_create_resource_pool
        # get us to default pool:
        test_2_view_pool

        # click on virtual machines pools tab
        @browser.click "//li[@id='nav_vmpool']/a"
        @browser.wait_for_condition(
               "selenium.isElementPresent(\"//div[@id='toolbar_nav']/ul/li[1]/a\")",
               10000)
        # click on 'new virtual machine pool'
        @browser.click "//div[@id='toolbar_nav']/ul/li[1]/a"

        # fill in required fields
        @browser.wait_for_condition(
               "selenium.isElementPresent(\"//input[@id='vm_resource_pool_name']\")",
               10000)
        @browser.type("//input[@id='vm_resource_pool_name']", "vm_resource_pool1")
        # click the button
        @browser.click "//form[@id='vm_pool_form']/div[2]/div[2]/div[2]/a"

        @pool_link="//ul[@id='nav_tree']/li/ul/li/div"
        @browser.wait_for_condition(
              "selenium.isElementPresent(\""+ @pool_link +"\")",
               10000)
     end

     #def test_4_create_start_stop_vm
     #   # view default pool's subpools
     #   @browser.wait_for_condition(
     #         "selenium.isElementPresent(\"//ul[@id='nav_tree']/li/span\")",
     #          10000)
     #   @browser.click(
     #       "//ul[@id='nav_tree']/li/span")  # click expand sublist checkbox

     #   # click on 'vm_resource_pool1' vm resource pool  link:
     #   @pool_link="//ul[@id='nav_tree']/li/ul/li/div"
     #   @browser.wait_for_condition(
     #         "selenium.isElementPresent(\""+ @pool_link +"\")",
     #          10000)
     #   @browser.click @pool_link
     #   @browser.wait_for_condition(
     #        "selenium.isElementPresent(\"//li[@id='nav_vmpool']/a\")",
     #         10000)
     #   # click on virtual machines tab
     #   @browser.click "//li[@id='nav_vmpool']/a"
     #   @browser.wait_for_condition(
     #          "selenium.isElementPresent(\"//div[@id='toolbar_nav']/ul/li[1]/a\")",
     #          10000)
     #   # click on 'add virtual machine'
     #   @browser.click "//div[@id='toolbar_nav']/ul/li[1]/a"

     #   # retrieve current # of vms
     #   num_vms = @browser.get_xpath_count "//table[@id='vms_grid']/tbody/tr"

     #   # fill in required fields
     #   @browser.wait_for_condition(
     #          "selenium.isElementPresent(\"//input[@id='vm_description']\")",
     #          10000)
     #   @browser.type("//input[@id='vm_description']", "zzz-selenium-test-vm")
     #   @browser.type("//input[@id='vm_num_vcpus_allocated']", "1")
     #   @browser.type("//input[@id='vm_memory_allocated_in_mb']", "256")
     #   # select 1st storage pool
     #   #@browser.click("//table[@id='storage_volumes_grid']/tbody/tr/td/div/input")
     #   @browser.wait_for_condition(
     #          "selenium.isElementPresent(\"//form[@id='vm_form']/div[2]/div[2]/div[2]/a\")",
     #          10000)
     #   # click the button
     #   @browser.click "//form[@id='vm_form']/div[2]/div[2]/div[2]/a"

     #   @browser.wait_for_condition(
     #        "selenium.isElementPresent(\"//table[@id='vms_grid']/tbody/tr[" + (num_vms.to_i + 1).to_s + "]\")",
     #         20000)
     #   # verify title of newly created vm
     #   assert_equal("zzz-selenium-test-vm",
     #      @browser.get_text("//table[@id='vms_grid']/tbody/tr[" + (num_vms.to_i + 1).to_s + "]/td[2]/div"))

     #   # start it, click checkbox, 'start vm', confirmation button; reload tab, check result
     #   @browser.click "//table[@id='vms_grid']/tbody/tr[" + (num_vms.to_i + 1).to_s + "]/td[1]/div/input"
     #   @browser.click "//div[@id='toolbar_nav']/ul/li[2]/ul/li[1]"
     #   @browser.wait_for_condition(
     #        "selenium.isElementPresent(\"//div[@id='vm_action_results']/div[3]/div/div[2]/a\")",
     #         10000)
     #   @browser.click "//div[@id='vm_action_results']/div[3]/div/div[2]/a"
     #   sleep 5 # give vm time to start
     #   @browser.click @pool_link
     #   @browser.wait_for_condition(
     #        "selenium.isElementPresent(\"//li[@id='nav_vmpool']/a\")",
     #         10000)
     #   # click on virtual machines tab
     #   @browser.click "//li[@id='nav_vmpool']/a"
     #   @browser.wait_for_condition(
     #        "selenium.isElementPresent(\"//table[@id='vms_grid']/tbody/tr[" + (num_vms.to_i + 1).to_s + "]/td[7]/div\") && " +
     #        "selenium.getText(\"//table[@id='vms_grid']/tbody/tr[" + (num_vms.to_i + 1).to_s + "]/td[7]/div\") == \"running\"",
     #         20000)
     #   #assert_equal("running",
     #     #@browser.get_text("//table[@id='vms_grid']/tbody/tr[" + (num_vms.to_i + 1).to_s + "]/td[7]/div"))

     #   # stop / destroy vm
     #   @browser.click "//table[@id='vms_grid']/tbody/tr[" + (num_vms.to_i + 1).to_s + "]/td[1]/div/input"
     #   @browser.click "//div[@id='toolbar_nav']/ul/li[2]/ul/li[2]"
     #   @browser.wait_for_condition(
     #        "selenium.isElementPresent(\"//div[@id='vm_action_results']/div[3]/div/div[2]/a\")",
     #         10000)
     #   @browser.click "//div[@id='vm_action_results']/div[3]/div/div[2]/a"
     #   sleep 5 # give vm time to stop
     #   @browser.click @pool_link
     #   @browser.wait_for_condition(
     #        "selenium.isElementPresent(\"//table[@id='vms_grid']/tbody/tr[" + (num_vms.to_i + 1).to_s + "]/td[7]/div\") && " +
     #        "selenium.getText(\"//table[@id='vms_grid']/tbody/tr[" + (num_vms.to_i + 1).to_s + "]/td[7]/div\") == \"stopped\"",
     #         20000)
     #   #assert_equal("stopped",
     #     #@browser.get_text("//table[@id='vms_grid']/tbody/tr[" + (num_vms.to_i + 1).to_s + "]/td[7]/div"))

     #end

 end

end
