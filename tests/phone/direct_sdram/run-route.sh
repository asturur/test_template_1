#!/bin/sh
set -eu
mkdir -p build/sim/unit-direct-sdram
iverilog -g2005 -s route_tb -o build/sim/unit-direct-sdram/route rtl/ngage_upp.v tests/phone/direct_sdram/route_tb.v
vvp build/sim/unit-direct-sdram/route
