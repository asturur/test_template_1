#!/bin/sh
set -eu
out=build/sim/unit-rf-mlab
mkdir -p "$out"
iverilog -g2001 -s tb -o "$out/test" rtl/arm/zap_register_file.sv tests/cpu/rf_mlab/tb.v > "$out/build.log" 2>&1
vvp "$out/test" > "$out/run.log" 2>&1
cat "$out/run.log"
if [ -n "${RF_INTEL_MODEL:-}" ]; then
 iverilog -g2001 -DSYNTHESIS -s tb -o "$out/vendor-test" rtl/arm/zap_register_file.sv "$RF_INTEL_MODEL" tests/cpu/rf_mlab/tb.v > "$out/vendor-build.log" 2>&1
 vvp "$out/vendor-test" > "$out/vendor-run.log" 2>&1
 cat "$out/vendor-run.log"
fi
