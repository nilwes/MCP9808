// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

// MCP9808 data sheet: https://ww1.microchip.com/downloads/en/DeviceDoc/25095A.pdf

import binary
import serial.device as serial
import serial.registers as serial

import gpio
import i2c

I2C_ADDRESS     ::= 0x18

class mcp9808:
  
  static DEVICE_ID_         ::=  0x04
  static MFCTR_ID_          ::=  0x54

  //Device Registers
  static DEVICE_ID_REG_       ::=  0b0000_0111
  static MFCTR_ID_REG_        ::=  0b0000_0110
  static SENSOR_CONFIG_REG_   ::=  0b0000_0001
  static AMBIENT_TEMP_REG_    ::=  0b0000_0101
  static UPPER_ALERT_REG_     ::=  0b0000_0010
  static LOWER_ALERT_REG_     ::=  0b0000_0011
  static CRITICAL_ALERT_REG_  ::=  0b0000_0100
  
  static ALERT_HYSTERESIS_ ::= { // Temperature trigger hysteresis in degrees Celsius
      "0.0"  : 0b00000_00_000000000,
      "1.5"  : 0b00000_01_000000000,
      "3.0"  : 0b00000_10_000000000,
      "6.0"  : 0b00000_11_000000000,
  }

  static ALERT_MODE_ ::= {
      "comparator"   : 0b00000_00_000001000,  // 2nd bit controls active HI or active LOW for the Alert pin
      "interrupt"    : 0b00000_00_000001001,  // Pull-Up resistor is requried if active LOW
                                              // 4th bit enables the Alert pin
  }

  reg_/serial.Registers ::= ?

  constructor dev/serial.Device:
    reg_ = dev.registers
    
    if (reg_.read_u16_le DEVICE_ID_REG_) != DEVICE_ID_: 
      throw "INVALID_CHIP_ID"
    if (reg_.read_u16_be MFCTR_ID_REG_)  != MFCTR_ID_: 
      throw "INVALID_MANUFACTURER_ID"
    
    reg_.write_u16_be SENSOR_CONFIG_REG_ 0x0000

  /**
  Enables the sensor. Note that the sensor is enabled by default after power-on.
  */
  enable:
    reg_.write_u16_be SENSOR_CONFIG_REG_ 0x0000
  
  /**
  Disables the sensor and puts it in low-power mode
  */
  disable:
    reg_status := reg_.read_u16_be SENSOR_CONFIG_REG_
    reg_.write_u16_be SENSOR_CONFIG_REG_  (reg_status | 0b0000_0001_0000_0000) //0x0100 Shutdown (Low-power mode)

  /**
  Reads the temperature.
  */
  read_temperature -> float:
    temp/float := 0.0
    t := reg_.read_u16_be AMBIENT_TEMP_REG_
    temp = (t & 0b0000_11111111_1111).to_float // Mask out Tcrit, Tupperm and Tlower flags
    temp = temp / 16
    if ((t & 0x1000) >> 12) == 1: // If sign bit set (negative temperature) 0b0001_0000_0000_0000
      temp = temp - 256

    //print_ "Alert set? 0x$(%x (reg_.read_u16_be SENSOR_CONFIG_REG_))"
    //print_ "Interrupt bits: 0x$(%x (t & 0xE000))"

    return temp

  /**
  Sets temperature alerts. A $hysteresis can be set to avoid triggering the alarm repeatedely
  if the temperature fluctuates around the alert temperature. The hysteresis is chosen by passing
  the corresponding string to the method. Possible string values for $hysteresis are
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

  There are three temperature limits that can be set: lower, upper, and critical. Please refer
  to the sensor data sheet for detailed information on how the interrupts behave in different
  temperature conditions. Default threshold temperatures are 0 degrees Celsius for both lower,
  upper, and critical.
  */
  set_alert 
      --lower/int       = 0 
      --upper/int       = 0
      --critical/int    = 0
      --hysteresis/string = "1.5" 
      --mode/string       = "comparator":

    reg_.write_u16_be SENSOR_CONFIG_REG_ ((reg_.read_u16_be SENSOR_CONFIG_REG_) | ALERT_HYSTERESIS_[hysteresis] | ALERT_MODE_[mode]) //Read reg, flip required bits, and write back
    print_ "regs1: 0x$(%x reg_.read_u16_be SENSOR_CONFIG_REG_)"

    reg_.write_i16_be UPPER_ALERT_REG_    (upper << 4)
    reg_.write_i16_be LOWER_ALERT_REG_    (lower << 4)
    reg_.write_i16_be CRITICAL_ALERT_REG_ (critical << 4)

    reg_.write_u16_be SENSOR_CONFIG_REG_ ((reg_.read_u16_be SENSOR_CONFIG_REG_) | 0x20) //set "clear int" bit #5

  /**
  Clears the alert bit.
  */
  clear_alert:
    reg_.write_u16_be SENSOR_CONFIG_REG_ 0b00000_00_000000000

  /**
  Reads the alert bit. If the temperature limit has been exceeded, the method returns '1'. If not, it returns '0'
  */
  read_alert -> int:
    return ((reg_.read_u16_be SENSOR_CONFIG_REG_) & 0x10) >> 4
 
  /**
  Clears the interrupt bit.
  */
  clear_interrupt:
    reg_.write_u16_be SENSOR_CONFIG_REG_ ((reg_.read_u16_be SENSOR_CONFIG_REG_) | 0x20) //set "clear int" bit #5

    

main:

  bus := i2c.Bus
    --sda=gpio.Pin 21
    --scl=gpio.Pin 22

  thermometer := bus.device I2C_ADDRESS
  temp_sensor := mcp9808 thermometer

  temp_sensor.set_alert --lower = 27 --upper = 30 --critical = 33 --hysteresis="0.0" --mode="comparator"

  60.repeat:
    sleep --ms=1000
    print_ "Temperature: $( temp_sensor.read_temperature)"
    if temp_sensor.read_alert == 1:
        print_ "High temperature detected!"
        sleep --ms=5000

  temp_sensor.disable