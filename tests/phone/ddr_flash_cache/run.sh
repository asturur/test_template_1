#!/bin/sh
set -eu
out=build/sim/unit-ddr-flash-cache
mkdir -p "$out"
sources='rtl/ngage_bram.v rtl/ngage_ddr_adapter.v rtl/ngage_ddr_lanes.sv rtl/ngage_ddr_stream.v rtl/ngage_ddr_stream_legacy.v rtl/ngage_ddr_flash_cache.v rtl/ngage_ddr_flash_adapter.v'
for mode in '0 0' '0 1' '8192 0' '8192 1' '16384 1' '32768 1'; do
    set -- $mode
    iverilog -g2012 -s tb -Ptb.CACHE_BYTES="$1" -Ptb.STREAM_TRANSPORT="$2" -o "$out/cache-$1-$2" $sources tests/phone/ddr_flash_cache/tb.sv
    vvp "$out/cache-$1-$2" > "$out/cache-$1-$2.log"
    cat "$out/cache-$1-$2.log"
    grep -q '^PASS D2 flash cache' "$out/cache-$1-$2.log"
done
