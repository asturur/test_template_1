#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
out=${1:-build/sim/unit-thumb-predict-alu}
mkdir -p "$out"
source=${ALU_FEEDBACK_RTL:-rtl/arm/zap_alu_main.sv}
docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
    --binary -j 4 --timing --assert -Wno-fatal -Wno-lint -Irtl/arm \
    --top-module test --Mdir "$out" "$source" tests/cpu/thumb_predict/alu.v > "$out/build.log" 2>&1
docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$root:/work" -w /work --entrypoint "/work/$out/Vtest" jotego/simulator:arm64
