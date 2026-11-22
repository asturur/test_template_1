#!/bin/sh
# Run inside the installed jotego/simulator:arm64 image.
set -eu
out=build/sim/unit-arm9v2-register-shift
mkdir -p "$out"
iverilog -g2001 -s shift_pipeline_tb -o "$out/test" \
    rtl/arm9v2/arm925t_phone.v tests/cpu/arm9v2_board/register_shift_tb.v
vvp "$out/test" > "$out/run.log"
cat "$out/run.log"
grep -q '^PASS rotate:' "$out/run.log"
