#!/bin/sh
set -eu
mkdir -p build/sim/unit-dirty
iverilog -g2012 -s tb -o build/sim/unit-dirty/test rtl/ngage_bram.v rtl/ngage_dirty_tracker.sv tests/phone/dirty_tracker/tb.sv
vvp build/sim/unit-dirty/test

iverilog -g2012 -s tb -Ptb.SECTORS=13 -o build/sim/unit-dirty/boundary rtl/ngage_bram.v rtl/ngage_dirty_tracker.sv tests/phone/dirty_tracker/tb.sv
vvp build/sim/unit-dirty/boundary
