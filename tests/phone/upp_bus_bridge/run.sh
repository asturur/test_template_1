#!/bin/sh
set -eu
mkdir -p build/sim/unit-upp-bus-bridge
iverilog -g2005 -s tb -o build/sim/unit-upp-bus-bridge/test rtl/ngage_upp.v tests/phone/upp_bus_bridge/tb.v
vvp build/sim/unit-upp-bus-bridge/test
