#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
mkdir -p build/sim/unit-tlb-lookup-owner
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
 --binary --timing --assert -Wno-fatal -Wno-lint -Irtl/arm --top-module test --Mdir build/sim/unit-tlb-lookup-owner \
 rtl/arm/zap_tlb.sv rtl/arm/zap_tlb_check.sv rtl/arm/zap_tlb_fsm.sv rtl/arm/zap_mem_inv_block.sv rtl/arm/zap_ram_simple.sv tests/cpu/tlb_lookup_owner/test.sv \
 > build/sim/unit-tlb-lookup-owner/build.log 2>&1
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint /work/build/sim/unit-tlb-lookup-owner/Vtest jotego/simulator:arm64
