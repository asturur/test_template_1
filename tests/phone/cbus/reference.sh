#!/bin/sh
set -eu
mkdir -p build/sim/unit-cbus
for profile in current-boot simif-board; do
 g++ -std=c++17 -O2 -I"scratch/$profile/board" tests/phone/cbus/reference.cpp "scratch/$profile/board/boot_profile.cpp" scratch/modem/ngage_modem.c -o "build/sim/unit-cbus/$profile"
 "build/sim/unit-cbus/$profile"
done
