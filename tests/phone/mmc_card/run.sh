#!/bin/sh
set -eu
out=${MMC_CARD_OUT:-build/sim/unit-mmc-card}
mkdir -p "$out"
for test in eof version; do
    iverilog -g2001 -s "${test}_tb" -o "$out/$test" rtl/ngage_mmc_dpram.v rtl/ngage_mmc_card.v "tests/phone/mmc_card/${test}_tb.v" > "$out/$test-build.log" 2>&1
    vvp "$out/$test" > "$out/$test.log"
    cat "$out/$test.log"
    grep -q '^PASS MMC ' "$out/$test.log"
done
