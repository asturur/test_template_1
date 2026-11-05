#!/bin/sh
set -eu
mkdir -p build/sim/unit-cbus
iverilog -g2012 -s tb -o build/sim/unit-cbus/test rtl/ngage_cbus_uem.v tests/phone/cbus/tb.sv
vvp build/sim/unit-cbus/test
