#!/bin/sh
set -eu
python3 tests/phone/save_manager/gen.py
iverilog -g2012 -s tb -o build/sim/unit-save-manager/test rtl/ngage_bram.v rtl/ngage_sd_sector.sv rtl/ngage_save_sector_bridge.sv rtl/ngage_save_header.sv rtl/ngage_dirty_tracker.sv rtl/ngage_save_manager.sv rtl/ngage_cflash.sv rtl/ngage_am29n643_state.v rtl/ngage_codeflash.sv rtl/ngage_rom_map.sv rtl/ngage_descramble.v rtl/ngage_flash_read_decode.v rtl/ngage_ddr_arbiter.sv rtl/ngage_ddr_adapter.sv rtl/ngage_ddr_lanes.sv tests/phone/save_manager/tb.sv
vvp build/sim/unit-save-manager/test
