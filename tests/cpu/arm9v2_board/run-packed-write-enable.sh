#!/bin/sh
# Run inside the installed jotego/simulator:arm64 image.
set -eu
out=${CACHE_WREN_OUT:-build/sim/unit-arm9v2-packed-write-enable}
mkdir -p "$out"
for bytes in 16 32; do
    iverilog -g2012 -s packed_write_enable_tb -Ppacked_write_enable_tb.LINE_BYTES="$bytes" \
        -o "$out/test-$bytes" rtl/arm9v2/arm925t_phone.v rtl/arm9v2/upstream/sim/stubs/altsyncram.sv \
        tests/cpu/arm9v2_board/packed_write_enable_tb.v
    vvp "$out/test-$bytes" > "$out/run-$bytes.log"
    cat "$out/run-$bytes.log"
    grep -q '^PASS packed cache WREN ' "$out/run-$bytes.log"
done
