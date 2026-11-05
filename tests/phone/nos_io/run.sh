#!/bin/sh
set -eu
mkdir -p build/sim/unit-nos-io
iverilog -g2012 -s tb -o build/sim/unit-nos-io/test rtl/ngage_nos_io.v tests/phone/nos_io/tb.sv
vvp build/sim/unit-nos-io/test
