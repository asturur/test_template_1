#!/bin/sh
set -eu
mkdir -p build/sim/unit-gpio-loopback
iverilog -g2005 -s tb -o build/sim/unit-gpio-loopback/test rtl/ngage_gpio_loopback.v tests/phone/gpio_loopback/tb.v
vvp build/sim/unit-gpio-loopback/test
