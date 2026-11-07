#!/bin/sh
set -eu
mkdir -p build/sim/unit-diagnostics
iverilog -g2005 -s tb -o build/sim/unit-diagnostics/test rtl/ngage_diagnostics.v tests/phone/diagnostics/tb.v
vvp build/sim/unit-diagnostics/test > build/sim/unit-diagnostics/run.log
cat build/sim/unit-diagnostics/run.log
grep -q '^PASS bounded diagnostic' build/sim/unit-diagnostics/run.log
