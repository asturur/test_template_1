#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
mkdir -p build/sim/unit-cache-access
cache_sources=""
reference_define=""
if [ -n "${CACHE_REFERENCE_DIR:-}" ]; then reference_define=-DNGAGE_CACHE_REFERENCE; fi
for source in rtl/arm920/write_buffer.sv rtl/arm920/cache_tags.sv rtl/ngage_bram.v rtl/arm920/cache_lines.sv rtl/arm920/cache_bank.sv rtl/arm920/cache_transfer.sv rtl/arm920/cache_refill.sv rtl/arm920/cache_maintenance.sv rtl/arm920/cache_access.sv; do
 if [ -n "${CACHE_REFERENCE_DIR:-}" ] && [ -f "$CACHE_REFERENCE_DIR/$(basename "$source")" ]; then
  cache_sources="$cache_sources $CACHE_REFERENCE_DIR/$(basename "$source")"
 else cache_sources="$cache_sources $source"; fi
done
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
 --binary --timing --assert $reference_define -Wno-fatal -Wno-lint --top-module test --Mdir build/sim/unit-cache-access \
 $cache_sources tests/cpu/cache_access/test.sv > build/sim/unit-cache-access/build.log 2>&1
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint /work/build/sim/unit-cache-access/Vtest jotego/simulator:arm64
