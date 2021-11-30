// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import gpio
import i2c
import ..src.MCP9808

temp_sensor := 0

main:

  bus := i2c.Bus
    --sda=gpio.Pin 21
    --scl=gpio.Pin 22

  int_pin := gpio.Pin 17 --input // NOTE: This pin requires a pull-up resistor

  thermometer := bus.device I2C_ADDRESS
  temp_sensor = mcp9808 thermometer --resolution = "0.25"
  temp_sensor.set_alert --lower = 27 --upper = 30 --critical = 33 --hysteresis = "0.0" --mode = "interrupt"

  60.repeat:
    print "Temperature: $(temp_sensor.read_temperature)"
    if int_pin.get == 0: // Interrupt pin active low
        print_warning
    sleep --ms=1000

  temp_sensor.disable

print_warning:
  print "INTERRUPT: Temperature out of bounds!"
  5.repeat:
    print "Clearing interrupt in $(5-it) seconds... "
    sleep --ms=1000
  temp_sensor.clear_interrupt