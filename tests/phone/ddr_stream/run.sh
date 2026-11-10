#!/bin/sh
# Run inside the existing jotego/simulator:arm64 image, network none.
set -eu
ulimit -c 0
out=build/sim/unit-ddr-stream
mkdir -p "$out"
verilator --cc --exe --build -Wno-fatal -Wno-lint --top-module ngage_ddr_stream --Mdir "$out/obj" rtl/ngage_bram.v rtl/ngage_ddr_stream.v "$PWD/tests/phone/ddr_stream/test.cpp" > "$out/build.log" 2>&1
"$out/obj/Vngage_ddr_stream" > "$out/run.log" 2>&1
cat "$out/run.log"
grep -q '^PASS D1 stream byte scoreboard' "$out/run.log"
