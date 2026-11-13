#!/bin/sh
set -eu
ulimit -c 0
ordered=${ORDERED_SAVE:-0}
out=build/sim/unit-raw-save-hps
if [ "$ordered" = 1 ]; then out=build/sim/unit-s3-raw-save-hps; fi
mkdir -p "$out"
mkdir -p build/sim/unit-raw-save-hps
python3 tests/phone/raw_save/prepare_hps.py
verilator --binary --timing -Wno-fatal -Wno-lint --top-module tb -GORDERED="$ordered" --Mdir "$out/obj" build/sim/unit-raw-save-hps/hps-compat.sv rtl/ngage_bram.v rtl/ngage_sd_sector.sv rtl/ngage_save_sector_bridge.v rtl/ngage_dirty_tracker.sv rtl/ngage_ordered_dirty_queue.v rtl/ngage_raw_save_manager.v rtl/ngage_reset_gate.v tests/phone/raw_save/hps_tb.sv > "$out/build.log" 2>&1
"$out/obj/Vtb" > "$out/run.log" 2>&1
cat "$out/run.log"
grep -q '^PASS actual three-slot' "$out/run.log"
