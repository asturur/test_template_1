#!/bin/sh
set -eu
python3 tests/phone/save_header/gen.py
iverilog -g2012 -s tb -o build/sim/unit-save-header/test rtl/ngage_save_header.sv tests/phone/save_header/tb.sv
vvp build/sim/unit-save-header/test
