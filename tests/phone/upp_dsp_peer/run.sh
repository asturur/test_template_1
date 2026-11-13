#!/bin/sh
set -eu
out=build/sim/unit-upp-dsp-peer
mkdir -p "$out"
iverilog -g2005 -s tb -o "$out/test" rtl/ngage_upp_dsp_peer.v tests/phone/upp_dsp_peer/tb.v
vvp "$out/test" > "$out/run.log"
cat "$out/run.log"
grep -q '^PASS UPP DSP peer' "$out/run.log"
