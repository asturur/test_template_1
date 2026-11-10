#!/bin/sh
set -eu
ulimit -c 0
out=build/sim/unit-raw-save-hps
mkdir -p "$out"
python3 tests/phone/raw_save/prepare_hps.py
verilator --binary --timing -Wno-fatal -Wno-lint --top-module tb --Mdir "$out/obj" "$out/hps-compat.sv" rtl/ngage_bram.v rtl/ngage_sd_sector.sv rtl/ngage_save_sector_bridge.sv rtl/ngage_dirty_tracker.sv rtl/ngage_raw_save_manager.v rtl/ngage_reset_gate.v rtl/ngage_diag_export.v tests/phone/raw_save/hps_tb.sv > "$out/build.log" 2>&1
"$out/obj/Vtb" > "$out/run.log" 2>&1
cat "$out/run.log"
grep -q '^PASS actual four-slot' "$out/run.log"
