#!/bin/sh
set -eu
out=build/sim/unit-ordered-dirty-queue
mkdir -p "$out"
for depth in 6 3; do
    iverilog -g2012 -s tb -Ptb.DEPTH="$depth" -o "$out/test-$depth" \
        rtl/ngage_bram.v rtl/ngage_ordered_dirty_queue.v tests/phone/ordered_dirty_queue/tb.sv
    vvp "$out/test-$depth" > "$out/run-$depth.log"
    cat "$out/run-$depth.log"
    grep -q '^PASS ordered dirty queue' "$out/run-$depth.log"
done
