#!/bin/sh
set -eu
ulimit -c 0
bulk=${BULK_PERSISTENCE:-0}
out=build/sim/unit-raw-save-full
if [ "$bulk" = 1 ]; then out=build/sim/unit-d3-raw-save-full; fi
mkdir -p "$out"
verilator --binary --timing -Wno-fatal -Wno-lint --top-module tb -GBULK="$bulk" --Mdir "$out/obj" rtl/ngage_bram.v rtl/ngage_sd_sector.sv rtl/ngage_save_sector_bridge.v rtl/ngage_dirty_tracker.sv rtl/ngage_ordered_dirty_queue.v rtl/ngage_raw_save_manager.v rtl/ngage_ddr_lanes.sv rtl/ngage_ddr_adapter.v rtl/ngage_ddr_stream.v rtl/ngage_ddr_stream_legacy.v rtl/ngage_ddr_flash_adapter.v rtl/ngage_ddr_flash_cache.v tests/phone/raw_save/full_tb.sv > "$out/build.log" 2>&1
"$out/obj/Vtb" > "$out/run.log" 2>&1
cat "$out/run.log"
grep -q '^PASS raw full-size' "$out/run.log"
