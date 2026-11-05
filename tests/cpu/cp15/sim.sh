#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
mkdir -p build/sim/unit-cp15
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
  --binary --timing --assert -Wno-fatal -Wno-lint -Irtl/arm --top-module test \
  --Mdir build/sim/unit-cp15 rtl/arm/zap_cp15_cb.sv tests/cpu/cp15/test.sv > build/sim/unit-cp15/build.log 2>&1
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint /work/build/sim/unit-cp15/Vtest jotego/simulator:arm64
