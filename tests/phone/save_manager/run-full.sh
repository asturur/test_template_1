#!/bin/sh
set -eu
python3 tests/phone/save_manager/full_gen.py
verilator --binary --timing -Wno-fatal --top-module tb --Mdir build/sim/unit-save-manager/full-obj rtl/ngage_bram.v rtl/ngage_sd_sector.sv rtl/ngage_save_sector_bridge.v rtl/ngage_save_header.sv rtl/ngage_dirty_tracker.sv rtl/ngage_save_manager.sv tests/phone/save_manager/full_tb.sv > build/sim/unit-save-manager/full-build.log 2>&1
build/sim/unit-save-manager/full-obj/Vtb
