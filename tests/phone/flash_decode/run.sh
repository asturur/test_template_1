#!/bin/sh
set -eu
python3 tests/phone/flash_decode/vectors.py
iverilog -g2012 -s tb -o build/sim/unit-flash-decode/test rtl/ngage_descramble.v rtl/ngage_flash_read_decode.v tests/phone/flash_decode/tb.sv
vvp build/sim/unit-flash-decode/test
