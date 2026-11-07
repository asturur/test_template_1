#!/bin/sh
set -eu
mkdir -p build/sim/unit-sparse-regs
iverilog -g2012 -s tb -o build/sim/unit-sparse-regs/test rtl/ngage_bram.v rtl/ngage_sparse_regs.v tests/phone/sparse_regs/tb.sv
vvp build/sim/unit-sparse-regs/test
for entries in 1 2 3 5 64; do
  iverilog -g2005 -s tb -Ptb.ENTRIES=$entries -o build/sim/unit-sparse-regs/conformance rtl/ngage_bram.v rtl/ngage_sparse_regs.v tests/phone/sparse_regs/conformance.v
  vvp build/sim/unit-sparse-regs/conformance
done
