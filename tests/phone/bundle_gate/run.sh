#!/bin/sh
set -eu
mkdir -p build/sim/unit-bundle-gate
iverilog -g2005 -s tb -o build/sim/unit-bundle-gate/test rtl/ngage_bundle_gate.v rtl/ngage_loader.sv tests/phone/bundle_gate/tb.v
vvp build/sim/unit-bundle-gate/test > build/sim/unit-bundle-gate/run.log
cat build/sim/unit-bundle-gate/run.log
grep -q '^PASS mounted, busy' build/sim/unit-bundle-gate/run.log
