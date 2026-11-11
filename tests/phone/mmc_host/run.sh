#!/bin/sh
set -eu
out=build/sim/unit-mmc-host
mkdir -p "$out"
iverilog -g2001 -Wall -s ngage_mmc_host -o "$out/strict" rtl/ngage_mmc_host.v > "$out/strict.log" 2>&1
iverilog -g2001 -s tb -o "$out/cmd16" rtl/ngage_mmc_host.v tests/phone/mmc_host/cmd16_tb.v > "$out/cmd16-build.log" 2>&1
vvp "$out/cmd16" > "$out/cmd16.log" 2>&1
grep '^PASS CMD16 ' "$out/cmd16.log"
for config in '4 16' '12 8'; do
    set -- $config
    divider=$1
    depth=$2
    stem="$out/data-$divider-$depth"
    iverilog -g2001 -s tb -Ptb.DIV="$divider" -Ptb.FIFO_DEPTH="$depth" -o "$stem" \
        rtl/ngage_mmc_host.v tests/phone/mmc_host/data_tb.v > "$stem-build.log" 2>&1
    vvp "$stem" > "$stem.log" 2>&1
    grep '^PASS MMC host data ' "$stem.log"
done
