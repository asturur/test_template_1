#!/bin/sh
set -eu
mkdir -p build/sim/unit-sdram
verilator --binary --timing -Wno-fatal --top-module tb --Mdir build/sim/unit-sdram/scrub-obj rtl/ngage_sdram_adapter.v tests/phone/sdram/scrub_tb.sv > build/sim/unit-sdram/scrub-build.log 2>&1
build/sim/unit-sdram/scrub-obj/Vtb
