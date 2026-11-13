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

# Exercise the actual 8,320-sector geometry, including cold metadata scrub.
# ALTERA_MF optionally selects the existing Intel altsyncram model as well.
for mode in behavioral vendor; do
    if [ "$mode" = vendor ]; then
        [ -n "${ALTERA_MF:-}" ] || continue
        ram="-DALTERA_RESERVED_QIS rtl/ngage_bram.v $ALTERA_MF"
    else
        ram=rtl/ngage_bram.v
    fi
    iverilog -g2001 -s fullsize_tb -o "$out/fullsize-$mode" \
        $ram rtl/ngage_ordered_dirty_queue.v tests/phone/ordered_dirty_queue/fullsize_tb.v \
        > "$out/build-fullsize-$mode.log" 2>&1
    vvp "$out/fullsize-$mode" > "$out/run-fullsize-$mode.log"
    cat "$out/run-fullsize-$mode.log"
    grep -q '^PASS full8320-sector queue' "$out/run-fullsize-$mode.log"
done
