#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
mkdir -p build/sim/unit-cache-transfer
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
 --binary --timing --assert -Wno-fatal -Wno-lint --top-module test --Mdir build/sim/unit-cache-transfer \
 rtl/arm920/cache_transfer.sv tests/cpu/cache_transfer/test.sv > build/sim/unit-cache-transfer/build.log 2>&1
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint /work/build/sim/unit-cache-transfer/Vtest jotego/simulator:arm64
