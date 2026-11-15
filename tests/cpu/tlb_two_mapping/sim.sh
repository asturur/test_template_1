#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
out=${1:-build/sim/unit-tlb-two-mapping}
mkdir -p "$out"
docker run --rm --pull=never --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
 --binary -j 4 --timing --assert -Wno-fatal -Wno-lint --top-module test --Mdir "$out" \
 rtl/ngage_bram.v rtl/arm920/tlb.sv rtl/arm920/tlb_bank.sv tests/cpu/tlb_two_mapping/test.sv > "$out/build.log" 2>&1
docker run --rm --pull=never --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint "/work/$out/Vtest" jotego/simulator:arm64
