#!/bin/sh
set -eu
mkdir -p build/sim/unit-cbus
iverilog -g2012 -s tb -o build/sim/unit-cbus/test rtl/ngage_bram.v rtl/ngage_cbus_uem.v tests/phone/cbus/tb.sv
vvp build/sim/unit-cbus/test

iverilog -g2012 -s tb -Ptb.POWERUP_STATUS=2 -o build/sim/unit-cbus/normal rtl/ngage_bram.v rtl/ngage_cbus_uem.v tests/phone/cbus/tb.sv
vvp build/sim/unit-cbus/normal
