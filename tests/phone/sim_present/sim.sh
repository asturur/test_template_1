#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
mkdir -p build/sim/unit-sim-present
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint bash jotego/simulator:arm64 -c 'cc -Wall -Wextra -Werror scratch/modem/ngage_modem.c tests/phone/sim_present/profile.c tests/phone/sim_present/test.c -o build/sim/unit-sim-present/test && build/sim/unit-sim-present/test'
