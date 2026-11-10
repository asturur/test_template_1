#!/bin/sh
set -eu
out=build/sim/unit-ddr-stream
mkdir -p "$out"
verilator --binary --timing -Wno-fatal -Wno-lint --top-module tb --Mdir "$out/fabric-obj" rtl/ngage_bram.v rtl/ngage_ddr_adapter.v rtl/ngage_ddr_lanes.sv rtl/ngage_ddr_stream.v rtl/ngage_ddr_stream_legacy.v rtl/ngage_ddr_rom_cache.v rtl/jtframe/ngage_jtframe_romrq_lcache.v rtl/ngage_ddr_arbiter.v tests/phone/ddr_stream/memory_peer.sv tests/phone/ddr_stream/fabric_tb.sv > "$out/fabric-build.log" 2>&1
"$out/fabric-obj/Vtb" > "$out/fabric-run.log" 2>&1
cat "$out/fabric-run.log"
grep -q '^PASS D1 existing arbiter' "$out/fabric-run.log"
