#!/bin/sh
# Run existing conformance against a locally installed Intel model and poison RAM.
set -eu
model=${1:?pass existing altera_mf.v}
out=build/sim/unit-boot-regs-vendor
mkdir -p "$out"
docker run --rm --pull=never --network none --platform linux/arm64 \
 --mount "type=bind,src=$PWD,dst=/src,readonly" \
 --mount "type=bind,src=$PWD/$out,dst=/out" \
 --mount "type=bind,src=$model,dst=/vendor/altera_mf.v,readonly" \
 --workdir /src --entrypoint sh jotego/simulator:arm64 -c '
set -eu
for mode in vendor poison; do
 if [ "$mode" = vendor ]; then ram="-DALTERA_RESERVED_QIS rtl/ngage_bram.v /vendor/altera_mf.v"; else ram=tests/cpu/cache_dirty_packed/poison_bram.v; fi
 iverilog -g2001 -s tb -o /out/test-$mode $ram rtl/ngage_bram_be.v rtl/ngage_boot_regs.v tests/phone/boot_regs/conformance.v > /out/build-$mode.log 2>&1
 vvp /out/test-$mode > /out/run-$mode.log 2>&1
 cat /out/run-$mode.log
done'
