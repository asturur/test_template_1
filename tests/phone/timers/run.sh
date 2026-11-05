#!/bin/sh
set -eu
mkdir -p build/sim/unit-timers
iverilog -g2012 -s tb -o build/sim/unit-timers/test rtl/ngage_timers.v tests/phone/timers/tb.sv
vvp build/sim/unit-timers/test
