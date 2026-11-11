#!/bin/sh
# Use an already available Intel simulation library; never fetch a toolchain.
set -eu
model=${1:?pass the existing altera_mf.v path}
test -f "$model"
model=$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' "$model")
out=${PHONE_TEST_OUT:-build/sim/unit-dma-channels-vendor}
mkdir -p "$out"
out=$(cd "$out" && pwd)
docker run --rm --pull=never --network none --platform linux/arm64 \
    --mount "type=bind,src=$PWD,dst=/src,readonly" \
    --mount "type=bind,src=$model,dst=/vendor/altera_mf.v,readonly" \
    --mount "type=bind,src=$out,dst=/out" \
    --entrypoint sh jotego/simulator:arm64 -c '
set -eu
for engines in 1 2 3; do
    iverilog -g2001 -DALTERA_RESERVED_QIS -s tb -Ptb.ENGINES=$engines \
        -o /out/test-$engines /vendor/altera_mf.v \
        /src/rtl/ngage_bram.v /src/rtl/ngage_dma_engine.v \
        /src/rtl/ngage_dma_channels.v /src/rtl/ngage_dma_route.v \
        /src/tests/phone/dma_channels/tb.v > /out/build-$engines.log 2>&1
    vvp /out/test-$engines > /out/run-$engines.log 2>&1
    grep "^PASS" /out/run-$engines.log
done'
