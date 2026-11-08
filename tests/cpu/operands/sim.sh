#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
mkdir -p build/sim/unit-operands
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
 --binary --timing --assert -Wno-fatal -Wno-lint -Irtl/arm --top-module test --Mdir build/sim/unit-operands \
 rtl/arm/zap_register_file.sv rtl/arm/zap_issue_main.sv tests/cpu/operands/test.sv > build/sim/unit-operands/build.log 2>&1
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint /work/build/sim/unit-operands/Vtest jotego/simulator:arm64
