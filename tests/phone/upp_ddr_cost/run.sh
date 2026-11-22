#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
src=tests/phone/upp_ddr_cost
out=build/sim/upp-ddr-cost
rev=53b707b
mkdir -p "$out/rtl"
files=(
    ngage_ddr_arbiter.v
    ngage_ddr_flash_adapter.v
    ngage_ddr_flash_cache.v
    ngage_ddr_adapter.v
    ngage_ddr_stream.v
    ngage_ddr_stream_legacy.v
    ngage_ddr_lanes.sv
    ngage_bram.v
)
sources=()
for file in "${files[@]}"; do
    git show "$rev:rtl/$file" > "$out/rtl/$file"
    sources+=("$out/rtl/$file")
done
iverilog -g2012 -s tb -o "$out/bench" "${sources[@]}" "$src/tb.sv"
vvp "$out/bench" | tee "$out/results.txt"
