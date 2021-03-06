# MCP9808
A Toit driver for the highly accurate MCP9808 temperature sensor.

Microchip Technology Inc.’s MCP9808 digital temperature sensor converts temperatures between -20°C and +100°C to a digital word with ±0.25°C/±0.5°C (typical/maximum) accuracy. The MCP9808 comes with user-programmable registers that provide flexibility for temperature sensing applications. The registers allow user-selectable settings such as Shutdown or Low-Power modes and the specification of temperature Alert window limits and critical output limits. When the temperature changes beyond the specified boundary limits, the MCP9808 outputs an Alert signal. The user has the option of setting the Alert output signal polarity as an active-low or activehigh comparator output for thermostat operation, or as a temperature Alert interrupt output for microprocessorbased systems. The Alert output can also be configured as a critical temperature output only.

## Usage

A simple usage example.

```
import MCP9808

main:
  ...
```

See the `examples` folder for more examples.

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: https://github.com/nilwes/MCP9808/issues
