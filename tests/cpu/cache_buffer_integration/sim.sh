#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
mkdir -p build/sim/unit-cache-buffer
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
 --binary --timing --assert -Wno-fatal -Wno-lint --top-module test --Mdir build/sim/unit-cache-buffer \
 rtl/arm920/write_buffer.sv rtl/arm920/cache_tags.sv rtl/ngage_bram.v rtl/arm920/cache_lines.sv rtl/arm920/cache_bank.sv rtl/arm920/cache_transfer.sv rtl/arm920/cache_refill.sv rtl/arm920/cache_maintenance.sv rtl/arm920/cache_access.sv tests/cpu/cache_buffer_integration/test.sv > build/sim/unit-cache-buffer/build.log 2>&1
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint /work/build/sim/unit-cache-buffer/Vtest jotego/simulator:arm64
