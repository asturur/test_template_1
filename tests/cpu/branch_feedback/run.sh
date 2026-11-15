#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
out=${1:-build/sim/unit-branch-feedback}
mkdir -p "$out"
docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
    --binary -j 4 --timing --assert -Wno-fatal -Wno-lint -Irtl/arm \
    --top-module test --Mdir "$out" rtl/arm/zap_btb.sv \
    rtl/arm/zap_ram_simple_nopipe.sv tests/cpu/branch_feedback/test.sv > "$out/build.log" 2>&1
docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$root:/work" -w /work --entrypoint "/work/$out/Vtest" jotego/simulator:arm64
