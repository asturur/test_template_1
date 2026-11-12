#!/bin/sh
set -eu
out=build/sim/unit-dma-ram-mux
mkdir -p "$out"
iverilog -g2001 -s tb -o "$out/test" rtl/ngage_dma_ram_mux.v tests/phone/dma_ram_mux/tb.v
vvp "$out/test" > "$out/run.log"
cat "$out/run.log"
grep -q '^PASS DMA RAM mux' "$out/run.log"
iverilog -g2001 -s capture_tb -o "$out/capture" rtl/ngage_dma_ram_mux.v rtl/ngage_sdram_arbiter.v tests/phone/dma_ram_mux/capture_tb.v
vvp "$out/capture" > "$out/capture.log"
cat "$out/capture.log"
grep -q '^PASS DMA RAM mux outer packet retention' "$out/capture.log"
