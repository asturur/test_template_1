#!/bin/sh
set -eu
out=build/sim/unit-upp-mdi
mkdir -p "$out"
iverilog -g2005 -s tb -o "$out/test" rtl/ngage_bram.v rtl/ngage_upp_dsp_peer.v rtl/ngage_upp_mdi.v tests/phone/upp_mdi/tb.v
vvp "$out/test" > "$out/run.log"
cat "$out/run.log"
grep -q '^PASS UPP MDI' "$out/run.log"
