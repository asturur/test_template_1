#!/bin/sh
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$repo_root"
mkdir -p build/sim/performance-baseline
iverilog -g2012 -s test -o build/sim/performance-baseline/tlb \
    rtl/ngage_bram.v rtl/arm920/tlb.sv rtl/arm920/tlb_bank.sv \
    docs/evidence/memory-performance-baseline/tlb_latency_tb.sv
vvp build/sim/performance-baseline/tlb
