#!/bin/sh
set -eu
out=build/sim/unit-dma-ram-mux
mkdir -p "$out"
iverilog -g2001 -s tb -o "$out/test" rtl/ngage_dma_ram_mux.v tests/phone/dma_ram_mux/tb.v
vvp "$out/test" > "$out/run.log"
cat "$out/run.log"
grep -q '^PASS DMA RAM mux' "$out/run.log"
