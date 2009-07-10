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

# Methods added to this helper will be available to all templates in the application.

require 'rubygems'
gem 'rails'
require 'erb'

module ApplicationHelper

  def text_field_with_label(label, obj, meth, opts = {}, divopts = {}) 
    opts[:class] = "textfield_effect"
    opts[:style]="width:250px;" unless opts[:style]
    divsclass = ""
    if divopts[:class]
      divclass = " class=#{divopts[:class]}"
    end
    %{ 
      <div class="field_title"><label for="#{obj}_#{meth}">#{_(label)}</label></div>
      <div class="form_field"#{divclass}>#{text_field obj, meth, opts}#{divopts[:afterfield] if divopts[:afterfield]}</div>
     }
  end

  def select_with_label(label, obj, meth, coll, opts={}) 
    opts[:class] = "dropdown_effect"
    opts[:style]="width:320px;" unless opts[:style]
    %{ 
      <div class="field_title"><label for="#{obj}_#{meth}">#{_(label)}</label></div>
      <div class="form_field">#{select obj, meth, coll, opts}</div>
     }
  end

  def select_tag_with_label(label, name, select_options, opts={}) 
    opts[:class] = "dropdown_effect"
    opts[:style]="width:320px;" unless opts[:style]
    %{ 
      <div class="field_title"><label for="#{name}">#{_(label)}</label></div>
      <div class="form_field">#{select_tag name, options_for_select(select_options), opts}</div>
     }
  end

  def hidden_field_with_label(label, obj, meth, display) 
    %{ 
      <div class="i"><label for="#{obj}_#{meth}">#{_(label)}</label>
      #{hidden_field obj, meth}<span class="hidden">#{display}</span></div>
     }
  end

  def hidden_field_tag_with_label(label, name, value, display) 
    %{ 
      <div class="i"><label for="#{name}">#{_(label)}</label>
      #{hidden_field_tag name, value}<span class="hidden">#{display}</span></div>
     }
  end

  def check_box_tag_with_label(label, name, value = "1", checked = false) 
    %{ 
      <div class="i"><label for="#{name}">#{_(label)}</label>
      #{check_box_tag name, value, checked}</div>
     }
  end

  def radio_button_tag_with_label(label, name, value = "1", checked = false) 
    %{ 
      <div class="i"><label for="#{name}">#{_(label)}</label>
      #{radio_button_tag name, value, checked}</div>
     }
  end

  # expects hash of labels => actions
  def multi_button_popup_footer(buttons = {})
      buttons_html = ""
      buttons.each{ |label, action|
       buttons_html+="<div class=\"button\">" +
                     " <div class=\"button_left_blue\"></div>" +
                     " <div class=\"button_middle_blue\"><a href=\"#\" onclick=\"#{action}\">#{label}</a></div>" +
                     " <div class=\"button_right_blue\"></div>" +
                     "</div>"
      }

   %{
      <div style="background: url(#{image_path "fb_footer.jpg"}) repeat-x; height: 37px; text-align:right; padding: 9px 9px 0 0; float: left; width: 97%;">
        <div class="button">
          <div class="button_left_grey"></div>
          <div class="button_middle_grey"><a href="#" onclick="$(document).trigger('close.facebox')">Cancel</a></div>
          <div class="button_right_grey"></div>
        </div>
        #{buttons_html}
      </div>
    }
  end

  def popup_footer(action, label)
    multi_button_popup_footer({label => action})
  end

  def ok_footer
    %{ 
      <div style="background: url(#{image_path "fb_footer.jpg"}) repeat-x; height: 37px; text-align:right; padding: 9px 9px 0 0;">
        <div class="button">
          <div class="button_left_grey"></div>
          <div class="button_middle_grey"><a href="#" onclick="$(document).trigger('close.facebox')">OK</a></div>
          <div class="button_right_grey"></div>
        </div>
      </div>
     }
  end

  def confirmation_dialog(div_id, text, action)
    %{
      <div id="#{div_id}" style="display:none;">
        <div class="confirm_dialog_title">
          <div class="confirm_dialog_header">#{text}</div>
          <div style="clear:both;"></div>
        </div>

        <div class="confirm_dialog_footer">
          <div class="button">
            <div class="button_left_grey"></div>
            <div class="button_middle_grey"><a href="#" onclick="$(document).trigger('close.facebox')">Cancel</a></div>
            <div class="button_right_grey"></div>
          </div>
          <div class="button">
            <div class="button_left_blue"></div>
            <div class="button_middle_blue"><a href="#" onclick="#{action}">OK</a></div>
            <div class="button_right_blue"></div>
          </div>
        </div>
      </div>
     }
  end

  def timeout_flash(name)
    %{
    <script type="text/javascript">
    // <![CDATA[
          var closeFlash = function() {$('#{name}').setStyle({'display':'none'})};
          setTimeout(closeFlash, 1000 * 45);
    // ]]>
    </script>
    }
  end

  def focus(field_name)
    %{
    <script type="text/javascript">
    // <![CDATA[
      Field.activate('#{field_name}');
    // ]]>
    </script>
    }
  end

  def flash_path(source)
    compute_public_path(source, 'swfs', 'swf')
  end

  def number_to_duration(input_num)
    input_int = input_num.to_i
    hours_to_seconds = [input_int/3600 % 24,
                        input_int/60 % 60,
                        input_int % 60].map{|t| t.to_s.rjust(2,'0')}.join(':')
    days = input_int / 86400
    day_str = ""
    if days > 0
      day_label = (days > 1) ? "days" : "day"
      day_str = "#{days} #{day_label} "
    end
    day_str + hours_to_seconds
  end
end
