#!/bin/sh
# Run inside the installed jotego/simulator:arm64 image.
set -eu
out=${BACKGROUND_LOCK_OUT:-build/sim/unit-arm9v2-background-lock}
mkdir -p "$out"
iverilog -g2001 -s background_load_lock_tb -o "$out/test" \
    rtl/arm9v2/arm925t_phone.v tests/cpu/arm9v2_board/background_load_lock_tb.v
vvp "$out/test" > "$out/run.log"
cat "$out/run.log"
grep -q '^PASS background load tags ' "$out/run.log"
