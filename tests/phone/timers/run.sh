#!/bin/sh
set -eu
out=${PHONE_TEST_OUT:-build/sim/unit-timers}
mkdir -p "$out"
for div in 1 3 4; do
  iverilog -g2001 -s tb -Ptb.DIV="$div" -o "$out/test-$div" rtl/ngage_timers.v tests/phone/timers/tb.sv
  vvp "$out/test-$div"
done
