#!/bin/sh
set -eu
mkdir -p build/sim/unit-reset-gate
iverilog -g2012 -s tb -o build/sim/unit-reset-gate/test rtl/ngage_reset_gate.v tests/phone/reset_gate/tb.sv
vvp build/sim/unit-reset-gate/test
