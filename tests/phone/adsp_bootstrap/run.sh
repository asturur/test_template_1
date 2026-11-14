#!/bin/sh
set -eu
out=build/sim/unit-adsp-bootstrap
mkdir -p "$out"
iverilog -g2005 -s tb -o "$out/test" rtl/ngage_adsp_bootstrap_tx.v tests/phone/adsp_bootstrap/tb.v
for rate in 78 104; do
    case "$rate" in
        78) half=6.410256 ;;
        104) half=4.807692 ;;
    esac
    vvp "$out/test" +half_period="$half" > "$out/run-$rate.log"
    cat "$out/run-$rate.log"
    grep -q '^PASS D550 bootstrap' "$out/run-$rate.log"
done
