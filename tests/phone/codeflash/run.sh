#!/bin/sh
set -eu
mkdir -p build/sim/unit-codeflash
iverilog -g2012 -s tb -o build/sim/unit-codeflash/test rtl/ngage_am29n643_state.v rtl/ngage_codeflash.sv rtl/ngage_rom_map.sv rtl/ngage_descramble.v rtl/ngage_flash_read_decode.v tests/phone/codeflash/tb.sv
vvp build/sim/unit-codeflash/test

iverilog -g2001 -s erase_tb -o build/sim/unit-codeflash/erase rtl/ngage_am29n643_state.v rtl/ngage_codeflash.sv rtl/ngage_rom_map.sv rtl/ngage_descramble.v rtl/ngage_flash_read_decode.v tests/phone/codeflash/erase_tb.v
for wait in 0 3; do
    vvp build/sim/unit-codeflash/erase +wait="$wait"
done
