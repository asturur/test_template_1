#!/bin/sh
# Run inside the existing jotego/simulator:arm64 image, network none.
set -eu
out=build/sim/unit-ddr-stream-bounds
mkdir -p "$out"
iverilog -g2012 -s bounds_tb -o "$out/test" \
    rtl/ngage_bram.v rtl/ngage_ddr_stream.v tests/phone/ddr_stream/bounds_tb.sv
vvp "$out/test" > "$out/run.log"
cat "$out/run.log"
grep -q '^PASS DDR bounds WRITE_FILL=0 admission_checks=98304$' "$out/run.log"
grep -q '^PASS DDR bounds WRITE_FILL=1 admission_checks=98304$' "$out/run.log"
