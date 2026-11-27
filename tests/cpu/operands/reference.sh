#!/bin/sh
# The original single-edge oracle is still executable against the pinned issue.
# Only this test build sees the reference module; production never compiles it.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
ref=scratch/timing-closure/slice1-operand/reference
mkdir -p "$ref" build/sim/unit-operands-reference
for source in zap_core.sv zap_writeback.sv zap_issue_main.sv zap_register_file.sv; do
 git show ef9b7621fa2ca90af250ce8d988260ebbc5e59d6:rtl/arm/$source > "$ref/$source"
done
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
 --binary --timing --assert -Wno-fatal -Wno-lint -Irtl/arm --top-module test --Mdir build/sim/unit-operands-reference \
 "$ref/zap_register_file.sv" "$ref/zap_issue_main.sv" tests/cpu/operands/reference-test.sv > build/sim/unit-operands-reference/build.log 2>&1
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint /work/build/sim/unit-operands-reference/Vtest jotego/simulator:arm64
