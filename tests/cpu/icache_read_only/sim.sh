#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
out=build/sim/unit-icache-read-only
mkdir -p "$out"
docker run --rm --pull=never --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
 --binary --timing --assert -Wno-fatal -Wno-lint --top-module test --Mdir "$out" \
 rtl/ngage_bram.v rtl/arm920/*.sv tests/cpu/icache_read_only/test.v > "$out/build.log" 2>&1
docker run --rm --pull=never --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint "/work/$out/Vtest" jotego/simulator:arm64 > "$out/run-wide.log" 2>&1
cat "$out/run-wide.log"
docker run --rm --pull=never --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint "/work/$out/Vtest" jotego/simulator:arm64 +halfword > "$out/run-halfword.log" 2>&1
cat "$out/run-halfword.log"
