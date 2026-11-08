#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
mkdir -p build/sim/unit-demand-completion
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
 --binary --timing --assert -Wno-fatal -Wno-lint --top-module test --Mdir build/sim/unit-demand-completion \
 rtl/ngage_bram.v rtl/arm920/*.sv tests/cpu/demand_completion/test.sv > build/sim/unit-demand-completion/build.log 2>&1
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint /work/build/sim/unit-demand-completion/Vtest jotego/simulator:arm64
