#!/bin/sh
set -eu
mkdir -p build/sim/unit-chip-boundaries
iverilog -g2005 -s tb -o build/sim/unit-chip-boundaries/test rtl/ngage_lrb2.v rtl/ngage_mjoelner.v tests/phone/chip_boundaries/tb.v
vvp build/sim/unit-chip-boundaries/test > build/sim/unit-chip-boundaries/run.log
cat build/sim/unit-chip-boundaries/run.log
grep -q '^PASS ' build/sim/unit-chip-boundaries/run.log
