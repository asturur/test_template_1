#!/bin/sh
# Run inside jotego/simulator:arm64. No vendor library is copied into the repo.
set -eu
out=build/sim/unit-bram
mkdir -p "$out"
iverilog -g2012 -s tb -o "$out/behavioral" rtl/ngage_bram.v tests/phone/bram/tb.v
vvp "$out/behavioral"
if [ -n "${ALTERA_MF:-}" ]; then
  iverilog -g2012 -DSYNTHESIS -s tb -o "$out/primitive" rtl/ngage_bram.v tests/phone/bram/tb.v "$ALTERA_MF" > "$out/vendor-build.log" 2>&1
  vvp "$out/primitive"
fi
