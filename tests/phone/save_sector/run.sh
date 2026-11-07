#!/bin/sh
set -eu
mkdir -p build/sim/unit-save-sector
iverilog -g2012 -s tb -o build/sim/unit-save-sector/test rtl/ngage_bram.v rtl/ngage_sd_sector.sv rtl/ngage_save_sector_bridge.sv tests/phone/save_sector/tb.sv
vvp build/sim/unit-save-sector/test
