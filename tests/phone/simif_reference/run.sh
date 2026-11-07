#!/bin/sh
set -eu
out=build/sim/unit-simif-reference
mkdir -p "$out"
g++ -std=c++17 -O2 -Iscratch/simif-board/board tests/phone/simif_reference/reference.cpp scratch/simif-board/board/boot_profile.cpp scratch/modem/ngage_modem.c -o "$out/reference"
for present in 0 1; do
 "$out/reference" "$present"
 iverilog -g2005 -s tb -Ptb.PRESENT=$present -o "$out/test" rtl/ngage_simif.v rtl/ngage_test_sim.v rtl/ngage_board.v rtl/ngage_upp.v rtl/ngage_upp_peripherals.v rtl/ngage_uem.v rtl/ngage_adsp.v rtl/ngage_lrb2.v rtl/ngage_mjoelner.v rtl/ngage_bram_be.v rtl/ngage_sparse_regs.v rtl/ngage_icu.v rtl/ngage_icu_extra.v rtl/ngage_timers.v rtl/ngage_nos_io.v rtl/ngage_mdi_stub.v rtl/ngage_cbus_uem.v rtl/ngage_gpio_loopback.v rtl/ngage_boot_regs.v rtl/ngage_trace_sink.v tests/phone/simif_reference/tb.v
 vvp "$out/test" > "$out/run.log"
 cat "$out/run.log"
 grep -q '^PASS SIMIF C++ comparison' "$out/run.log"
done
