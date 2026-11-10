#!/bin/sh
set -eu
out=build/sim/unit-ddr-stream
mkdir -p "$out"
verilator --cc --exe --build -Wno-fatal -Wno-lint --top-module ngage_ddr_stream --Mdir "$out/obj" rtl/ngage_bram.v rtl/ngage_ddr_stream.v "$PWD/tests/phone/ddr_stream/test.cpp" > "$out/overlap-build.log" 2>&1
"$out/obj/Vngage_ddr_stream" --overlap > "$out/overlap-run.log" 2>&1
cat "$out/overlap-run.log"
grep -q '^PASS D1 overlap' "$out/overlap-run.log"
sources='rtl/ngage_bram.v rtl/ngage_ddr_adapter.v rtl/ngage_ddr_lanes.sv rtl/ngage_ddr_stream.v rtl/ngage_ddr_stream_legacy.v rtl/ngage_ddr_rom_cache.v rtl/jtframe/ngage_jtframe_romrq_lcache.v'
for stream in 0 1; do
 verilator --binary --timing -Wno-fatal -Wno-lint --top-module tb -GSTREAM_TRANSPORT="$stream" --Mdir "$out/overlap-adapter-$stream-obj" $sources tests/phone/ddr_stream/adapter_overlap_tb.sv > "$out/overlap-adapter-$stream-build.log" 2>&1
 "$out/overlap-adapter-$stream-obj/Vtb" > "$out/overlap-adapter-$stream-run.log" 2>&1
 cat "$out/overlap-adapter-$stream-run.log"
 grep -q '^PASS D1 adapter overlap' "$out/overlap-adapter-$stream-run.log"
done
