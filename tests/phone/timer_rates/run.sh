#!/bin/sh
set -eu
out=${PHONE_TEST_OUT:-build/sim/unit-timer-rates}
mkdir -p "$out"
for hz in 78000000 104000000; do
    iverilog -g2001 -s tb -Ptb.SYS_CLK_HZ="$hz" -o "$out/test-$hz" \
        rtl/ngage_bram.v rtl/ngage_timers.v rtl/ngage_nos_io.v tests/phone/timer_rates/tb.sv
    vvp "$out/test-$hz"
done
