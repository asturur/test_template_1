#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
mkdir -p build/sim/unit-cp15-rf
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
 --binary --timing --assert -DNGAGE_RUNTIME_TRACE -Wno-fatal -Wno-lint -Irtl/arm --top-module test --Mdir build/sim/unit-cp15-rf \
 rtl/arm/zap_register_file.sv rtl/arm/zap_writeback.sv rtl/arm/zap_btb.sv tests/cpu/cp15_rf/test.sv > build/sim/unit-cp15-rf/build.log 2>&1
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint /work/build/sim/unit-cp15-rf/Vtest jotego/simulator:arm64 +ngage-compact-trace
