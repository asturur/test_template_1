#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
cd "$root"
out=${1:-build/sim/unit-cache-certificate}
mkdir -p "$out"
python3 tests/cpu/cache_certificate/fixture.py "$out/test.v"
rtl=""
for file in rtl/arm920/*.sv; do
 if [ "$file" = rtl/arm920/cache_access.sv ]; then file=${CACHE_ACCESS_RTL:-$file}; fi
 rtl="$rtl $file"
done
docker run --rm --pull=never --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
 --binary -j 3 --timing --assert -Wno-fatal -Wno-lint --top-module test -GEXPECTED_REUSE="${CERT_REUSE:-8}" --Mdir "$out" \
 rtl/ngage_bram.v $rtl "$out/test.v" > "$out/build.log" 2>&1
docker run --rm --pull=never --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint "/work/$out/Vtest" jotego/simulator:arm64 > "$out/run.log" 2>&1
cat "$out/run.log"
