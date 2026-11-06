#!/bin/sh
set -eu
mkdir -p build/sim/unit-timer-conformance
iverilog -g2005 -s tb -o build/sim/unit-timer-conformance/test rtl/ngage_timers.v rtl/ngage_icu.v tests/phone/timer_conformance/tb.v
for profile in current-boot simif-board; do
 g++ -std=c++17 -O2 -I"scratch/$profile/board" tests/phone/timer_conformance/reference.cpp "scratch/$profile/board/boot_profile.cpp" scratch/modem/ngage_modem.c -o "build/sim/unit-timer-conformance/$profile"
 "build/sim/unit-timer-conformance/$profile"
 vvp build/sim/unit-timer-conformance/test > "build/sim/unit-timer-conformance/$profile.log"
 grep -q "^PASS timer IRQ edges" "build/sim/unit-timer-conformance/$profile.log"
 cat "build/sim/unit-timer-conformance/$profile.log"
done
