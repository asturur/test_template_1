#!/bin/sh
set -eu
mkdir -p build/sim/unit-timer-rates
for hz in 78000000 104000000; do
    iverilog -g2012 -s tb -Ptb.SYS_CLK_HZ="$hz" -o build/sim/unit-timer-rates/test \
        rtl/ngage_timers.v rtl/ngage_nos_io.v tests/phone/timer_rates/tb.sv
    vvp build/sim/unit-timer-rates/test
done
