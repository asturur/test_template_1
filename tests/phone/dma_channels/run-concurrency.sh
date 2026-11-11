#!/bin/sh
set -eu
out=${PHONE_TEST_OUT:-build/sim/unit-dma-concurrency}
docker run --rm --pull=never --network none --platform linux/arm64 \
 -e PHONE_TEST_OUT="$out" -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -c '
set -eu
out=$PHONE_TEST_OUT
mkdir -p "$out"
for engines in 1 2 3; do
 verilator --binary --timing --assert -j 2 -Wno-fatal -Wno-lint \
  --top-module concurrency_tb -GENGINES="$engines" --Mdir "$out/obj-$engines" \
  rtl/ngage_bram.v rtl/ngage_dma_engine.v rtl/ngage_dma_channels.v rtl/ngage_dma_route.v \
  rtl/ngage_lcd_stream.v rtl/ngage_dma_ram_mux.v rtl/ngage_sdram_arbiter.v \
  tests/phone/dma_channels/concurrency_tb.v > "$out/build-$engines.log" 2>&1
 for mode in 0 1 2; do
  "$out/obj-$engines/Vconcurrency_tb" +mode="$mode" > "$out/run-$engines-$mode.log" 2>&1
  grep '^PASS' "$out/run-$engines-$mode.log"
 done
done
'
