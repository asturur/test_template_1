#!/bin/sh
# The donor tree is mounted read-only; all build products remain in this tree.
set -eu
donor=${NGAGE2_DONOR:?Set NGAGE2_DONOR to the pinned ngage2 checkout}
out=${MMC_CARD_DONOR_OUT:-build/sim/unit-mmc-card-donor}
test -f "$donor/sim/harness/mmc_main.cpp"
python3 - "$donor" <<'CHECK_PINS'
import hashlib, sys
from pathlib import Path
pins = {
    'mmc_card.sv': '3dad56b55982c4589b173850066ca4e8297c68d88fb376d7529912ac5f73c434',
    'tdp_ram.sv': 'e235b8c071c5b2faa97bc263d51f1e79e7ad52786be4edb7bf2667c4e91fe344',
}
for name, expected in pins.items():
    path = Path(sys.argv[1]) / 'rtl' / 'board' / name
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise SystemExit('Donor source pin mismatch: ' + str(path))
CHECK_PINS
mkdir -p "$out"
docker run --rm --pull=never --network none --platform linux/arm64 \
    -v "$PWD:/work" -v "$donor:/donor:ro" -w /work \
    -e MMC_CARD_DONOR_OUT="$out" --entrypoint sh jotego/simulator:arm64 -c '
set -eu
for version in donor port equivalence; do
    out="$MMC_CARD_DONOR_OUT/$version"
    mkdir -p "$out"
    if [ "$version" = donor ]; then
        top=mmc_card
        language=1800-2017
        set -- /donor/rtl/board/tdp_ram.sv /donor/rtl/board/mmc_card.sv
    elif [ "$version" = equivalence ]; then
        top=mmc_card_equivalence
        language=1800-2017
        set -- /donor/rtl/board/tdp_ram.sv /donor/rtl/board/mmc_card.sv \
            rtl/ngage_mmc_dpram.v rtl/ngage_mmc_card.v tests/phone/mmc_card/equivalence.v
    else
        top=ngage_mmc_card
        language=1364-2001
        set -- rtl/ngage_mmc_dpram.v rtl/ngage_mmc_card.v
    fi
    verilator --cc --exe --build -j 4 -O3 --x-assign unique --x-initial unique \
        -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN \
        --language "$language" --prefix Vmmc_card --top-module "$top" \
        --Mdir "$out/obj" -o Vmmc_card -CFLAGS "-O2 -std=c++17 -I/donor/sim/harness" \
        "$@" /donor/sim/harness/mmc_main.cpp > "$out/build.log" 2>&1
    "$out/obj/Vmmc_card" +verilator+seed+1 +verilator+rand+reset+2 --seed 1 > "$out/run.log" 2>&1
    cat "$out/run.log"
    grep -q "mmc_card: all checks passed" "$out/run.log"
done
out="$MMC_CARD_DONOR_OUT/public-equivalence"
mkdir -p "$out"
for test in eof version; do
    sed "s/ngage_mmc_card dut(/mmc_card_equivalence dut(/" "tests/phone/mmc_card/${test}_tb.v" > "$out/${test}_tb.v"
    iverilog -g2012 -s "${test}_tb" -o "$out/$test" \
        /donor/rtl/board/tdp_ram.sv /donor/rtl/board/mmc_card.sv \
        rtl/ngage_mmc_dpram.v rtl/ngage_mmc_card.v tests/phone/mmc_card/equivalence.v \
        "$out/${test}_tb.v" > "$out/$test-build.log" 2>&1
    vvp "$out/$test" > "$out/$test.log"
    cat "$out/$test.log"
    grep -q "^PASS MMC " "$out/$test.log"
done
'
