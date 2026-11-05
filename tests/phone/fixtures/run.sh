#!/bin/sh
set -eu
mkdir -p build/sim/unit-phone-fixtures
for profile in current-boot simif-board; do
 g++ -std=c++17 -O2 -I"scratch/$profile/board" tests/phone/fixtures/board_transactions.cpp "scratch/$profile/board/boot_profile.cpp" scratch/modem/ngage_modem.c -o "build/sim/unit-phone-fixtures/$profile"
 "build/sim/unit-phone-fixtures/$profile" > "build/sim/unit-phone-fixtures/$profile.tsv"
 diff -u "tests/phone/fixtures/$profile.tsv" "build/sim/unit-phone-fixtures/$profile.tsv"
done
printf '%s\n' 'PASS current and staged board transaction fixtures'
