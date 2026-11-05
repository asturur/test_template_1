#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
mkdir -p build/sim/unit-cache-refill
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
 --binary --timing --assert -Wno-fatal -Wno-lint --top-module test --Mdir build/sim/unit-cache-refill \
 rtl/arm920/cache_tags.sv rtl/arm920/cache_lines.sv rtl/arm920/cache_bank.sv rtl/arm920/cache_transfer.sv rtl/arm920/cache_refill.sv tests/cpu/cache_refill/test.sv > build/sim/unit-cache-refill/build.log 2>&1
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint /work/build/sim/unit-cache-refill/Vtest jotego/simulator:arm64
