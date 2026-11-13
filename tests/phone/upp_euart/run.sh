#!/bin/sh
set -eu
out=build/sim/unit-upp-euart
mkdir -p "$out"
iverilog -g2005 -s tb -o "$out/test" rtl/ngage_bram.v rtl/ngage_upp_euart.v tests/phone/upp_euart/tb.v
vvp "$out/test" > "$out/run.log"
cat "$out/run.log"
grep -q '^PASS UPP EUART' "$out/run.log"
