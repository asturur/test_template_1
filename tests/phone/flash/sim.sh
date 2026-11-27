#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
mkdir -p build/sim/unit-phone-flash
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint g++ jotego/simulator:arm64 \
 -std=c++17 -O2 -I/work/scratch/current-boot/board tests/phone/flash/test.cpp scratch/current-boot/board/boot_profile.cpp scratch/modem/ngage_modem.c -o build/sim/unit-phone-flash/test
 docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint /work/build/sim/unit-phone-flash/test jotego/simulator:arm64
