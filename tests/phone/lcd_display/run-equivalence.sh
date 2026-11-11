#!/bin/sh
set -eu
out=build/sim/unit-lcd-equivalence
mkdir -p "$out"
iverilog -g2001 -s equivalence_tb -o "$out/test" rtl/ngage_bram.v rtl/ngage_lcd_display.v tests/phone/lcd_display/reference.v tests/phone/lcd_display/equivalence_tb.v > "$out/build.log" 2>&1
vvp "$out/test" > "$out/run.log" 2>&1
cat "$out/run.log"
grep -q '^PASS LCD cycle equivalence' "$out/run.log"
