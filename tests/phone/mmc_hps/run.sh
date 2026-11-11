#!/bin/sh
set -eu
out=${MMC_HPS_OUT:-build/sim/unit-mmc-hps}
mkdir -p "$out"
iverilog -g2001 -s tb -o "$out/direct" rtl/ngage_mmc_hps.v tests/phone/mmc_hps/tb.v > "$out/direct-build.log" 2>&1
vvp "$out/direct" > "$out/direct.log"
cat "$out/direct.log"
grep -q '^PASS MMC HPS direct' "$out/direct.log"
MMC_HPS_OUT="$out" python3 tests/phone/mmc_hps/prepare_hps.py
verilator --binary --timing --assert -j 3 -Wno-fatal -Wno-lint --top-module actual_tb --Mdir "$out/obj" "$out/hps-compat.sv" rtl/ngage_mmc_hps.v rtl/ngage_mmc_card.v rtl/ngage_mmc_dpram.v tests/phone/mmc_hps/actual_tb.sv > "$out/actual-build.log" 2>&1
"$out/obj/Vactual_tb" > "$out/actual.log" 2>&1
cat "$out/actual.log"
grep -q '^PASS actual four-slot MMC HPS' "$out/actual.log"
