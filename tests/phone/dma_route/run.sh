#!/bin/sh
set -eu
out=build/sim/unit-dma-route
mkdir -p "$out"
iverilog -g2001 -s tb -o "$out/test" rtl/ngage_dma_route.v rtl/ngage_sdram_arbiter.v \
    rtl/ngage_bram.v rtl/ngage_bram_be.v tests/phone/dma_route/tb.v
vvp "$out/test" > "$out/run.log"
cat "$out/run.log"
grep -q '^PASS DMA route' "$out/run.log"
