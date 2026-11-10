#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
mkdir -p build/sim/unit-icache-discard
sources=""
for source in rtl/arm920/*.sv; do
 if [ "$source" = rtl/arm920/cache_access.sv ]; then source=${CACHE_ACCESS_RTL:-$source}; fi
 sources="$sources $source"
done
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
 --binary --timing --assert -Wno-fatal -Wno-lint --top-module test --Mdir build/sim/unit-icache-discard \
 rtl/ngage_bram.v $sources tests/cpu/icache_discard/test.sv > build/sim/unit-icache-discard/build.log 2>&1
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint /work/build/sim/unit-icache-discard/Vtest jotego/simulator:arm64
