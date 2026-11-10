#!/bin/sh
set -eu
out=build/sim/unit-ddr-stream
mkdir -p "$out"
sources='rtl/ngage_bram.v rtl/ngage_ddr_adapter.v rtl/ngage_ddr_lanes.sv rtl/ngage_ddr_stream.v rtl/ngage_ddr_stream_legacy.v rtl/ngage_ddr_rom_cache.v rtl/jtframe/ngage_jtframe_romrq_lcache.v'
verilator --binary --timing -Wno-fatal -Wno-lint --top-module tb --Mdir "$out/equiv-obj" $sources tests/phone/ddr_stream/memory_peer.sv tests/phone/ddr_stream/equivalence_tb.sv > "$out/equiv-build.log" 2>&1
"$out/equiv-obj/Vtb" > "$out/equiv-run.log" 2>&1
cat "$out/equiv-run.log"
for bits in 64 128 256; do
for line in 0 1; do
 iverilog -g2012 -s tb -Ptb.STREAM_TRANSPORT=1 -Ptb.LINE_REFILL="$line" -Ptb.LINE_BITS="$bits" -o "$out/cache-$bits-$line" $sources tests/phone/ddr_rom_cache/tb.sv
 vvp "$out/cache-$bits-$line" > "$out/cache-$bits-$line.log"
 grep '^PASS DDR ROM cache' "$out/cache-$bits-$line.log"
done
done
