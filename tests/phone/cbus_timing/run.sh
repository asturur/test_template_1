#!/bin/sh
set -eu
for profile in current-boot simif-board; do
 out="build/sim/unit-cbus-timing-$profile"
 mkdir -p "$out"
 verilator --cc --exe --build -j 2 -Wno-fatal --top-module ngage_cbus_uem --Mdir "$out" -CFLAGS "-I/work/scratch/$profile/board" rtl/ngage_bram.v rtl/ngage_cbus_uem.v /work/tests/phone/cbus_timing/reference.cpp "/work/scratch/$profile/board/boot_profile.cpp" /work/scratch/modem/ngage_modem.c > "$out/build.log" 2>&1
 "$out/Vngage_cbus_uem"
done
