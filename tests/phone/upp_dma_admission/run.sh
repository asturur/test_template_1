#!/bin/sh
set -eu
out=build/sim/unit-upp-dma-admission
mkdir -p "$out"
iverilog -g2001 -s tb -o "$out/test" rtl/ngage_upp.v tests/phone/upp_dma_admission/tb.v
vvp "$out/test"
