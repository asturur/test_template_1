#!/bin/sh
set -eu
out=${PHONE_TEST_OUT:-build/sim/unit-sparse-regs}
mkdir -p "$out"
iverilog -g2012 -s tb -o "$out"/test rtl/ngage_bram.v rtl/ngage_sparse_regs.v tests/phone/sparse_regs/tb.sv
vvp "$out"/test
for entries in 1 2 3 5 64; do
  iverilog -g2001 -s tb -Ptb.ENTRIES=$entries -o "$out"/conformance rtl/ngage_bram.v rtl/ngage_sparse_regs.v tests/phone/sparse_regs/conformance.v
  vvp "$out"/conformance
done
