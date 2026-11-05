#!/bin/sh
set -eu
mkdir -p build/sim/unit-sd-sector
iverilog -g2012 -s tb -o build/sim/unit-sd-sector/test rtl/ngage_sd_sector.sv tests/phone/sd_sector/tb.sv
vvp build/sim/unit-sd-sector/test
