#!/bin/sh
set -eu
out=build/sim/unit-register-ram
mkdir -p "$out"
iverilog -g2001 -s tb -o "$out/test" rtl/ngage_bram.v rtl/ngage_timers.v rtl/ngage_icu.v tests/phone/register_ram/reference_timers.v tests/phone/register_ram/reference_icu.v tests/phone/register_ram/tb.v > "$out/build.log" 2>&1
vvp "$out/test" > "$out/run.log" 2>&1
cat "$out/run.log"
