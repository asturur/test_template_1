#!/bin/sh
set -eu
model=${1:?pass existing altera_mf.v}
out=build/sim/unit-register-ram-vendor
mkdir -p "$out"
docker run --rm --pull=never --network none --platform linux/arm64 \
 --mount "type=bind,src=$PWD,dst=/src,readonly" \
 --mount "type=bind,src=$PWD/$out,dst=/out" \
 --mount "type=bind,src=$model,dst=/vendor/altera_mf.v,readonly" \
 --workdir /src --entrypoint sh jotego/simulator:arm64 -c '
set -eu
for mode in vendor poison; do
 if [ "$mode" = vendor ]; then ram="-DALTERA_RESERVED_QIS rtl/ngage_bram.v /vendor/altera_mf.v"; else ram="tests/cpu/cache_dirty_packed/poison_bram.v"; fi
 iverilog -g2001 -s tb -o /out/test-$mode $ram rtl/ngage_timers.v rtl/ngage_icu.v tests/phone/register_ram/reference_timers.v tests/phone/register_ram/reference_icu.v tests/phone/register_ram/tb.v > /out/build-$mode.log 2>&1
 vvp /out/test-$mode > /out/run-$mode.log 2>&1
 cat /out/run-$mode.log
done'
