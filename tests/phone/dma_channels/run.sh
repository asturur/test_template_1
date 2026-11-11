#!/bin/sh
set -eu
docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -c '
set -eu
for engines in 1 3; do
    out=build/sim/unit-dma-channels-$engines
    mkdir -p "$out"
    verilator --binary --timing --assert -j 2 -Wno-fatal -Wno-lint \
        --top-module tb -GENGINES=$engines --Mdir "$out/obj" \
        rtl/ngage_dma_engine.v rtl/ngage_dma_channels.v rtl/ngage_dma_route.v \
        tests/phone/dma_channels/tb.v > "$out/build.log" 2>&1
    "$out/obj/Vtb" > "$out/run.log" 2>&1
    grep "^PASS DMA channels" "$out/run.log"
done'
