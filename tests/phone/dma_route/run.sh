#!/bin/sh
set -eu
out=build/sim/unit-dma-route
mkdir -p "$out"
iverilog -g2001 -s tb -o "$out/test" rtl/ngage_dma_route.v rtl/ngage_sdram_arbiter.v \
    rtl/ngage_bram.v rtl/ngage_bram_be.v tests/phone/dma_route/tb.v
vvp "$out/test" > "$out/run.log"
cat "$out/run.log"
grep -q '^PASS DMA route' "$out/run.log"

iverilog -g2001 -s response_tb -o "$out/response" rtl/ngage_dma_route.v tests/phone/dma_route/response_tb.v
vvp "$out/response" > "$out/response.log"
cat "$out/response.log"
grep -q '^PASS local DMA registered response' "$out/response.log"

iverilog -g2001 -s ram_admission_tb -o "$out/ram-admission" \
    rtl/ngage_dma_route.v tests/phone/dma_route/ram_admission_tb.v
vvp "$out/ram-admission" > "$out/ram-admission.log"
cat "$out/ram-admission.log"
grep -q '^PASS DMA RAM admission' "$out/ram-admission.log"
