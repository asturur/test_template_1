#!/bin/sh
# Run inside the simulator image; isolated from all checkpoint simulations.
set -eu
out="${OUT_DIR:-build/sim/unit-uem-clock-rate}"
for hz in 78000000 104000000; do
 mkdir -p "$out/$hz"
 verilator --cc --exe --build -j 2 -Wno-fatal --top-module ngage_uem_clock -GCLK_HZ="$hz" --Mdir "$out/$hz" rtl/ngage_cbus_uem.v /work/tests/phone/uem_clock/rate.cpp > "$out/$hz/build.log" 2>&1
 "$out/$hz/Vngage_uem_clock" "$hz"
done
