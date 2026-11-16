#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
out=${1:-build/sim/unit-cache-admit-probe}
mkdir -p "$out"
rtl=""
for file in rtl/arm920/*.sv; do
 if [ "$file" = rtl/arm920/cache_access.sv ]; then file=${CACHE_ACCESS_RTL:-$file}; fi
 rtl="$rtl $file"
done
docker run --rm --pull=never --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
 --binary -j 3 --timing --assert -Wno-fatal -Wno-lint --top-module test --Mdir "$out" \
 rtl/ngage_bram.v $rtl tests/cpu/cache_admit_probe/test.v > "$out/build.log" 2>&1
docker run --rm --pull=never --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint "/work/$out/Vtest" jotego/simulator:arm64
