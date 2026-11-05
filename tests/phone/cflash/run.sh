#!/bin/sh
set -eu
mkdir -p build/sim/unit-cflash
iverilog -g2012 -s tb -o build/sim/unit-cflash/test rtl/ngage_cflash.sv tests/phone/cflash/tb.sv
vvp build/sim/unit-cflash/test
