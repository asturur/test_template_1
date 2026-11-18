#!/bin/sh
set -eu
mkdir -p build/sim/unit-cbus
for profile in current-boot simif-board; do
 g++ -std=c++17 -O2 -I"tests/phone/reference/$profile/board" tests/phone/cbus/reference.cpp "tests/phone/reference/$profile/board/boot_profile.cpp" tests/phone/reference/modem/ngage_modem.c -o "build/sim/unit-cbus/$profile"
 "build/sim/unit-cbus/$profile"
done
