// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

// MCP9808 data sheet: https://ww1.microchip.com/downloads/en/DeviceDoc/25095A.pdf

import serial.device as serial
import serial.registers as serial

I2C_ADDRESS     ::= 0x18

class mcp9808:
  
  static DEVICE_ID_           ::=  0x04
  static MFCTR_ID_            ::=  0x54

  //Device Registers
  static DEVICE_ID_REG_         ::=  0b0000_0111
  static MFCTR_ID_REG_          ::=  0b0000_0110
  static SENSOR_CONFIG_REG_     ::=  0b0000_0001
  static AMBIENT_TEMP_REG_      ::=  0b0000_0101
  static UPPER_ALERT_REG_       ::=  0b0000_0010
  static LOWER_ALERT_REG_       ::=  0b0000_0011
  static CRITICAL_ALERT_REG_    ::=  0b0000_0100
  static SENSOR_RESOLUTION_REG_  ::=  0b0000_1000
  
  static SENSOR_RESOLUTION_ ::= { // Temperature trigger hysteresis in degrees Celsius
      "0.5"     : 0b0000_0000,
      "0.25"    : 0b0000_0001,
      "0.125"   : 0b0000_0010,
      "0.0625"  : 0b0000_0011,
  }

  static ALERT_HYSTERESIS_ ::= { // Temperature trigger hysteresis in degrees Celsius
      "0.0"  : 0b00000_00_000000000,
      "1.5"  : 0b00000_01_000000000,
      "3.0"  : 0b00000_10_000000000,
      "6.0"  : 0b00000_11_000000000,
  }

  static ALERT_MODE_ ::= {                    // 1st bit sets comparator/interrupt mode
      "comparator"   : 0b00000_00_000001000,  // 2nd bit controls active HI or active LOW for the Alert pin
      "interrupt"    : 0b00000_00_000001001,  // (Pull-Up resistor is requried if active LOW)
                                              // 4th bit enables the Alert pin
  }

  reg_/serial.Registers ::= ?

  /**
  The constructor takes the temperature measurement $resolution in degrees Celsius as only input. Valid values are
  "0.5" 
  "0.25" <-- Default value
  "0.125"
  "0.0625"
  */
  constructor dev/serial.Device --resolution/string = "0.25":
    reg_ = dev.registers
    
    if (reg_.read_u16_le DEVICE_ID_REG_) != DEVICE_ID_: 
      throw "INVALID_CHIP_ID"
    if (reg_.read_u16_be MFCTR_ID_REG_)  != MFCTR_ID_: 
      throw "INVALID_MANUFACTURER_ID"
    
    reg_.write_u8 SENSOR_RESOLUTION_REG_ SENSOR_RESOLUTION_[resolution]
    reg_.write_u16_be SENSOR_CONFIG_REG_ 0x0000
  
  /**
  Enables the sensor. Note that the sensor is enabled by default after power-on.
  */
  enable -> none:
    reg_.write_u16_be SENSOR_CONFIG_REG_ 0x0000
  
  /**
  Disables the sensor and puts it in low-power mode
  */
  disable -> none:
    reg_status := reg_.read_u16_be SENSOR_CONFIG_REG_
    reg_.write_u16_be SENSOR_CONFIG_REG_  (reg_status | 0b0000_0001_0000_0000) //0x0100 Shutdown (Low-power mode)

  /**
  Reads the temperature and returns it in degrees Celsius.
  */
  read_temperature -> float:
    temp/float := 0.0
    t := reg_.read_u16_be AMBIENT_TEMP_REG_
    temp = (t & 0b0000_11111111_1111).to_float // Mask out Tcrit, Tupper and Tlower flags
    temp = temp / 16
    if ((t & 0x1000) >> 12) == 1: // If sign bit set (negative temperature) 0b0001_0000_0000_0000
      temp = temp - 256

    return temp

  /**
  Sets temperature alerts. A hysteresis can be set to avoid triggering the alarm repeatedely
  if the temperature fluctuates around the alert temperature. The hysteresis is chosen by passing
  the corresponding string to the method. Possible string values for hysteresis are
  "0.0" -> 0.0 degrees Celsius
  "1.5" -> 1.5 degrees Celsius  <-- Default value
  "3.0" -> 3.0 degrees Celsius
  "6.0" -> 6.0 degrees Celsius
  
  The alert can be in either comparator mode, or interrupt mode. In comparator mode, when the
  temperature returns to the allowed temperature range, the alert is cleared. In interrupt mode,
  the interrupt flag must be manually cleared by calling the $clear_interrupt method.
  The mode is chosen by passing the corresponding string to the method. Valid values for $mode are:
  "comparator" --> Comparator mode  <-- Default mode
  "interrupt"  --> Interrupt mode
  NOTE:  If the sensor is in alert mode "Interrupt", the alert will not disapper if the temperature
  enters the valid range again. Only a call to $clear_interrupt will reset the alert.

  There are three temperature limits that can be set: lower, upper, and critical. Please refer
  to the sensor data sheet for detailed information on how the interrupts behave in different
  temperature conditions. Default threshold temperatures are 0 degrees Celsius for both lower,
  upper, and critical.

  NOTE: The chip alert output pin (pin 3) is active LOW and a pull-up resistor is required. See 
  MCP9808 data sheet, page 30, figure 5-9.
  */
  set_alert -> none
      --lower/int       = 0 
      --upper/int       = 0
      --critical/int    = 0
      --hysteresis/string = "1.5"
      --mode/string       = "comparator":

    reg_.write_u16_be SENSOR_CONFIG_REG_ ((reg_.read_u16_be SENSOR_CONFIG_REG_) | ALERT_HYSTERESIS_[hysteresis] | ALERT_MODE_[mode])
    reg_.write_i16_be UPPER_ALERT_REG_    (upper << 4) //TODO: Allow for floating point temperature limits
    reg_.write_i16_be LOWER_ALERT_REG_    (lower << 4)
    reg_.write_i16_be CRITICAL_ALERT_REG_ (critical << 4)

  /**
  Reads the temperature alert bit. If the temperature boundaries has been exceeded, the method returns True. If not, it returns False
  */
  read_alert -> bool:
    if (((reg_.read_u16_be SENSOR_CONFIG_REG_) & 0x0010) >> 4) == 1:
      return true
    else:
      return false

  /**
  Reads three bits that indicates where the ambient temperature is in relation to the defined temperature limits. 
  Please refer to the MCP9808 data sheet, page 32, figure 5-10 for details.
  */
  read_alert_bits -> int:
    return ((reg_.read_u16_be AMBIENT_TEMP_REG_) & 0xE000) >> 13
 
  /**
  Clears the interrupt bit.
  */
  clear_interrupt -> none:
    reg_.write_u16_be SENSOR_CONFIG_REG_ ((reg_.read_u16_be SENSOR_CONFIG_REG_) | 0x0020)
