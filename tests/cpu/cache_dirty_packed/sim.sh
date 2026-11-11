#!/bin/sh
# Compare production cache against the pre-packing implementation cycle by cycle.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
out=build/sim/unit-cache-dirty-packed
test=tests/cpu/cache_dirty_packed
mkdir -p "$out"
docker run --rm --pull=never --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
 --binary --timing --assert -Wno-fatal -Wno-lint --top-module test --Mdir "$out" \
 rtl/ngage_bram.v rtl/arm920/*.sv "$test"/reference_*.sv "$test/access_equivalence.sv" > "$out/build.log" 2>&1
docker run --rm --pull=never --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint "/work/$out/Vtest" jotego/simulator:arm64 > "$out/run.log" 2>&1
cat "$out/run.log"
