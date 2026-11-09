#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
mkdir -p build/sim/unit-write-buffer
buffer_source=rtl/arm920/write_buffer.sv
reference_define=""
if [ -n "${WB_REFERENCE_DIR:-}" ]; then
 buffer_source="$WB_REFERENCE_DIR/write_buffer.sv"
 reference_define=-DNGAGE_WB_REFERENCE
fi
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
 --binary --timing --assert $reference_define -Wno-fatal -Wno-lint --top-module test --Mdir build/sim/unit-write-buffer \
 "$buffer_source" tests/cpu/write_buffer/test.sv > build/sim/unit-write-buffer/build.log 2>&1
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint /work/build/sim/unit-write-buffer/Vtest jotego/simulator:arm64

docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
 --binary --timing --assert $reference_define -Wno-fatal -Wno-lint --top-module hazard_test --Mdir build/sim/unit-write-buffer-hazards \
 "$buffer_source" tests/cpu/write_buffer/hazard_test.sv > build/sim/unit-write-buffer-hazards-build.log 2>&1
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint /work/build/sim/unit-write-buffer-hazards/Vhazard_test jotego/simulator:arm64
