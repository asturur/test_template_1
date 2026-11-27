#!/bin/sh
set -eu
python3 -B tests/phone/upp_ddr_ram/prepare.py
docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$PWD:/work" -w /work --entrypoint /bin/sh jotego/simulator:arm64 -ec '
    out=build/sim/upp-ddr-ram
    sh "$out/peripherals.sh"
    sh "$out/mixed/build.sh"
    ulimit -c 0
    if ! "$out/mixed/obj/Vtb" +upp_stress > "$out/mixed/production.log" 2>&1; then
        cat "$out/mixed/production.log"
        exit 1
    fi
    grep "^PASS" "$out/mixed/production.log"
'
