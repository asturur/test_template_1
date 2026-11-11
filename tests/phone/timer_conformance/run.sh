#!/bin/sh
set -eu
out=${PHONE_TEST_OUT:-build/sim/unit-timer-conformance}
mkdir -p "$out"
iverilog -g2001 -s tb -o "$out/test" rtl/ngage_bram.v rtl/ngage_timers.v rtl/ngage_icu.v tests/phone/timer_conformance/tb.v
vvp "$out/test"
