#!/bin/sh
set -eu
mkdir -p build/sim/unit-icu
iverilog -g2012 -s tb -o build/sim/unit-icu/test rtl/ngage_icu.v tests/phone/icu/tb.sv
vvp build/sim/unit-icu/test
