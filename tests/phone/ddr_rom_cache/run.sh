#!/bin/sh
set -eu
out=build/sim/unit-ddr-rom-cache
mkdir -p "$out"
iverilog -g2012 -s tb -o "$out/test" rtl/ngage_bram.v rtl/jtframe/ngage_jtframe_romrq_lcache.v rtl/ngage_ddr_rom_cache.v rtl/ngage_ddr_adapter.sv rtl/ngage_ddr_lanes.sv tests/phone/ddr_rom_cache/tb.sv
vvp "$out/test" > "$out/run.log"
cat "$out/run.log"
grep -q '^PASS DDR ROM cache' "$out/run.log"
