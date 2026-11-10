#!/bin/sh
set -eu
ulimit -c 0
stream=${STREAM_TRANSPORT:-0}
cache=${FLASH_CACHE_BYTES:-0}
bulk=${BULK_PERSISTENCE:-0}
out=build/sim/unit-raw-save-nor
if [ "$stream" = 1 ]; then out=build/sim/unit-d1-raw-save-nor; fi
if [ "$cache" != 0 ]; then out="build/sim/unit-d2-raw-save-nor-$cache-$stream"; fi
if [ "$bulk" = 1 ]; then out="build/sim/unit-d3-raw-save-nor-$cache-$stream"; fi
mkdir -p "$out"
mkdir -p build/sim/unit-raw-save-hps
python3 tests/phone/raw_save/prepare_hps.py
verilator --binary --timing -Wno-fatal -Wno-lint --top-module tb -GSTREAM_TRANSPORT="$stream" -GFLASH_CACHE_BYTES="$cache" -GBULK="$bulk" --Mdir "$out/obj" build/sim/unit-raw-save-hps/hps-compat.sv rtl/ngage_bram.v rtl/ngage_sd_sector.sv rtl/ngage_save_sector_bridge.v rtl/ngage_dirty_tracker.sv rtl/ngage_ordered_dirty_queue.v rtl/ngage_raw_save_manager.v rtl/ngage_diag_export.v rtl/ngage_cflash.sv rtl/ngage_am29n643_state.v rtl/ngage_codeflash.sv rtl/ngage_rom_map.sv rtl/ngage_descramble.v rtl/ngage_flash_read_decode.v rtl/ngage_ddr_arbiter.v rtl/ngage_ddr_adapter.v rtl/ngage_ddr_lanes.sv rtl/ngage_ddr_stream.v rtl/ngage_ddr_stream_legacy.v rtl/ngage_ddr_flash_cache.v rtl/ngage_ddr_flash_adapter.v tests/phone/raw_save/nor_tb.sv > "$out/build.log" 2>&1
"$out/obj/Vtb" > "$out/run.log" 2>&1
cat "$out/run.log"
grep -q '^PASS raw NOR' "$out/run.log"
