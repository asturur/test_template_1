#!/bin/sh
set -eu
out=build/sim/dsp-full-product-repro-20261116
mkdir -p "$out"
python3 tests/cpu/dsp_full_product/generate_vectors.py
docker run --rm --pull=never --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint verilator jotego/simulator:arm64 --binary --timing --assert -j 3 -Wno-fatal -Wno-lint -Irtl/arm --top-module test --Mdir "$out/obj" rtl/arm/zap_shifter_multiply.sv tests/cpu/dsp_full_product/candidate.sv tests/cpu/dsp_full_product/tb.v > "$out/build.log" 2>&1
docker run --rm --pull=never --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint "/work/$out/obj/Vtest" jotego/simulator:arm64 > "$out/run.log" 2>&1
cat "$out/run.log"
