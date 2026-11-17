#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
out=${1:-build/sim/cache-resident-stream-$(date +%Y%m%d-%H%M%S)}
if [ -e "$out" ]; then
    echo "Output directory already exists: $out" >&2
    exit 1
fi
mkdir -p "$out"
python3 tests/cpu/cache_resident_stream/report.py snapshot "$out"
docker run --rm --pull=never --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
 --binary -j 4 --timing --assert -Wno-fatal -Wno-lint --top-module test --Mdir "$out" \
 rtl/ngage_bram.v rtl/arm920/*.sv tests/cpu/cache_resident_stream/test.v > "$out/build.log" 2>&1
for run in normal repeat negative; do
    arg=
    if [ "$run" = negative ]; then arg=+corrupt_expected; fi
    if docker run --rm --pull=never --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint "/work/$out/Vtest" jotego/simulator:arm64 $arg > "$out/$run.log" 2>&1; then
        if [ "$run" = negative ]; then echo "Negative control unexpectedly passed" >&2; exit 1; fi
    else
        if [ "$run" != negative ]; then cat "$out/$run.log"; exit 1; fi
        if ! rg -q 'checker byte mismatch \(negative control=1\)' "$out/$run.log"; then cat "$out/$run.log"; exit 1; fi
    fi
done
python3 tests/cpu/cache_resident_stream/report.py report "$out"
rg 'SUMMARY|HIST|VERIFIED|PASS' "$out/normal.log"
echo 'PASS: exact repeat and deliberate wrong-byte rejection'
