#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
mkdir -p build/sim/unit-tlb64-bank
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
 --binary --timing --assert -Wno-fatal -Wno-lint --top-module test --Mdir build/sim/unit-tlb64-bank \
 rtl/ngage_bram.v rtl/arm920/tlb_bank.sv tests/cpu/tlb64_bank/test.sv > build/sim/unit-tlb64-bank/build.log 2>&1
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint /work/build/sim/unit-tlb64-bank/Vtest jotego/simulator:arm64
