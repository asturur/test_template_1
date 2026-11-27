#!/bin/sh
# Run inside the existing simulator container, from the repository root.
set -eu
mkdir -p build/sim/unit scratch/mister-migration-plan
run_dir=$(mktemp -d scratch/mister-migration-plan/fulltest.XXXXXX)
bundle="$run_dir/test.bundle"
trap 'rm -f "$bundle" "$bundle.json"; rmdir "$run_dir"' EXIT HUP INT TERM
python3 tools/prepare_mister_images.py --profile diagnostic-erased-pmm --output "$bundle"
verilator --cc --exe --build -j 2 -Wno-fatal --top-module full_bundle --Mdir build/sim/unit/obj-full-bundle \
 rtl/ngage_loader.sv rtl/ngage_ddr_arbiter.v rtl/ngage_ddr_adapter.v rtl/ngage_ddr_lanes.sv \
 tests/phone/mister_transport/full_bundle.sv /work/tests/phone/mister_transport/full_bundle.cpp > build/sim/unit/full-bundle-build.log 2>&1
build/sim/unit/obj-full-bundle/Vfull_bundle "$bundle"
