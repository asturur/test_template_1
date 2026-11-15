#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
out=${1:-build/sim/unit-fifo-flags}
mkdir -p "$out"
python3 tests/cpu/fifo_flags/exhaustive.py > "$out/exhaustive.json"
docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
    --binary -j 4 --timing --assert -Wno-fatal --top-module test --Mdir "$out" \
    rtl/arm/zap_sync_fifo.sv tests/cpu/fifo_flags/test.sv > "$out/build.log" 2>&1
docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$root:/work" -w /work --entrypoint "/work/$out/Vtest" jotego/simulator:arm64
