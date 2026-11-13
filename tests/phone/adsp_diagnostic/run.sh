#!/bin/sh
set -eu
out=build/sim/unit-adsp-diagnostic
mkdir -p "$out"
iverilog -g2005 -s tb -o "$out/test" rtl/ngage_aic23.v rtl/ngage_adsp_diagnostic.v tests/phone/adsp_diagnostic/tb.v
for rate in 78 104; do
    case "$rate" in
        78) half=6.410256 ;;
        104) half=4.807692 ;;
    esac
    vvp "$out/test" +half_period="$half" > "$out/run-$rate.log"
    cat "$out/run-$rate.log"
    grep -q '^PASS D550 diagnostic42' "$out/run-$rate.log"
done
