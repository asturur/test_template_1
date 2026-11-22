#!/bin/sh
# Run inside the installed jotego/simulator:arm64 image.
set -eu
out=${BACKGROUND_LOCK_OUT:-build/sim/unit-arm9v2-background-lock}
mkdir -p "$out"
for owned in 0 1; do
    iverilog -g2001 -s background_load_lock_tb -Pbackground_load_lock_tb.OWNED="$owned" \
        -o "$out/test-$owned" rtl/arm9v2/arm925t_phone.v \
        tests/cpu/arm9v2_board/background_load_lock_tb.v
    vvp "$out/test-$owned" > "$out/run-$owned.log"
    grep '^PASS background load tags ' "$out/run-$owned.log"
done
cmp "$out/run-0.log" "$out/run-1.log"
