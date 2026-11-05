#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
mkdir -p build/sim/unit-tlb-bus-gate
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
 --binary --timing --assert -Wno-fatal -Wno-lint --top-module test --Mdir build/sim/unit-tlb-bus-gate \
 rtl/arm920/tlb_bus_gate.sv tests/cpu/tlb_bus_gate/test.sv > build/sim/unit-tlb-bus-gate/build.log 2>&1
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint /work/build/sim/unit-tlb-bus-gate/Vtest jotego/simulator:arm64
