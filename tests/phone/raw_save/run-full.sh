#!/bin/sh
set -eu
ulimit -c 0
out=build/sim/unit-raw-save-full
mkdir -p "$out"
verilator --binary --timing -Wno-fatal -Wno-lint --top-module tb --Mdir "$out/obj" rtl/ngage_bram.v rtl/ngage_sd_sector.sv rtl/ngage_save_sector_bridge.sv rtl/ngage_dirty_tracker.sv rtl/ngage_raw_save_manager.v tests/phone/raw_save/full_tb.sv > "$out/build.log" 2>&1
"$out/obj/Vtb" > "$out/run.log" 2>&1
cat "$out/run.log"
grep -q '^PASS raw full-size' "$out/run.log"
