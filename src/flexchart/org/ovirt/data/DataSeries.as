/*
 Copyright (C) 2008 Red Hat, Inc.
 Written by Steve Linabery <slinabery@redhat.com>

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; version 2 of the License.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 MA  02110-1301, USA.  A copy of the GNU General Public License is
 also available at http://www.gnu.org/copyleft/gpl.html.
*/

//class to encapsulate the json object representation of a data
//series returned from stats package

package org.ovirt.data {

  public class DataSeries {

    private var object:Object;
    private var dataPoints:Array;
    private var description:String;
    private var maxValue:Number;

    public function DataSeries (object:Object) {
      this.object = object;
      this.description = object["description"] as String;
      dataPoints = new Array();
      var inDataPoints:Array = object["vectors"] as Array;
      for (var i:int = 0; i < inDataPoints.length; i++) {
        dataPoints.push(new DataPoint((inDataPoints[i] as Array)[0] as String,
                                  (inDataPoints[i] as Array)[1] as Number,
                                  description));
      }
      maxValue = object["max_value"] as Number;
    }

    public function getDataPoints():Array {
      return dataPoints;
    }

    public function getMaxValue():Number {
      return maxValue;
    }
  }
}
