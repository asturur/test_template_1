#!/bin/sh
set -eu
out=${DMA_ENGINE_OUT:-build/sim/unit-dma-engine}
mkdir -p "$out"
iverilog -g2001 -s tb -o "$out/test" rtl/ngage_dma_engine.v tests/phone/dma_engine/tb.v
if ! vvp "$out/test" > "$out/run.log"; then
    cat "$out/run.log"
    exit 1
fi
cat "$out/run.log"
grep -q '^PASS DMA engine' "$out/run.log"
