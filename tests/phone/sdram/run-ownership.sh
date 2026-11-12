#!/bin/sh
# Run inside the existing simulator image; no phone/media or frozen runs used.
set -eu
out=${SDRAM_OWNER_OUT:-build/sim/unit-sdram-ownership}
mkdir -p "$out"
sources='rtl/ngage_sdram_arbiter.v rtl/ngage_sdram_adapter.v tests/phone/sdram/ownership_tb.sv'
for delay in 0 3 7; do
    iverilog -g2012 -DSDRAM_SHARED_PAYLOAD -s ownership_tb \
        -Pownership_tb.TAKE_WAIT="$delay" -o "$out/owner-$delay" $sources
    vvp "$out/owner-$delay" > "$out/owner-$delay.log" 2>&1
    if grep -Ei 'error|fatal|warning|violation' "$out/owner-$delay.log"; then exit 1; fi
    grep '^PASS shared SDRAM ownership' "$out/owner-$delay.log"
done
# A new owner overwriting the old write during logical-reset drain must fail.
iverilog -g2012 -DSDRAM_SHARED_PAYLOAD -DOMIT_OWNER_GUARD -s ownership_tb \
    -o "$out/no-owner-guard" $sources
if vvp "$out/no-owner-guard" > "$out/no-owner-guard.log" 2>&1; then
    echo 'FAIL ownership guard negative control unexpectedly passed'; exit 1
fi
grep -q 'outer SDRAM write payload changed before drain' "$out/no-owner-guard.log"
echo 'PASS negative control: unguarded new owner corrupts reset-drain payload'
