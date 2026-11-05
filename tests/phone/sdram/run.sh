#!/bin/sh
set -eu
mkdir -p build/sim/unit-sdram
iverilog -g2012 -s tb -o build/sim/unit-sdram/test rtl/ngage_sdram_adapter.v rtl/ngage_sdram_arbiter.v rtl/sdram/jtframe_sdram64*.v scratch/sdram-reference/mt48lc16m16a2.v tests/phone/sdram/tb.sv
vvp build/sim/unit-sdram/test > build/sim/unit-sdram/run.log
if grep -E 'ERROR:|FATAL:' build/sim/unit-sdram/run.log; then exit 1; fi
cat build/sim/unit-sdram/run.log
iverilog -g2012 -s tb -o build/sim/unit-sdram/arbiter rtl/ngage_sdram_arbiter.v tests/phone/sdram/arbiter_tb.sv
vvp build/sim/unit-sdram/arbiter
