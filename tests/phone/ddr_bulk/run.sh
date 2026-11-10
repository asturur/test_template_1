#!/bin/sh
set -eu
out=build/sim/unit-ddr-bulk
mkdir -p "$out"
iverilog -g2012 -s tb -o "$out/test" rtl/ngage_bram.v rtl/ngage_ddr_lanes.sv \
    rtl/ngage_ddr_arbiter.v rtl/ngage_ddr_adapter.v rtl/ngage_ddr_stream.v \
    rtl/ngage_ddr_stream_legacy.v rtl/ngage_ddr_flash_adapter.v rtl/ngage_ddr_flash_cache.v \
    tests/phone/ddr_bulk/tb.sv
vvp "$out/test" > "$out/run.log"
cat "$out/run.log"
grep -q '^PASS D3 DDR ownership' "$out/run.log"
