#!/bin/sh
set -eu
mkdir -p build/sim/unit-sparse-regs
iverilog -g2012 -s tb -o build/sim/unit-sparse-regs/test rtl/ngage_bram.v rtl/ngage_sparse_regs.v tests/phone/sparse_regs/tb.sv
vvp build/sim/unit-sparse-regs/test
