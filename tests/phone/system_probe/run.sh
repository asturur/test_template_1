#!/bin/sh
set -eu
mkdir -p build/sim/unit-system-probe
iverilog -g2005 -s tb -o build/sim/unit-system-probe/test rtl/ngage_mmc_host.v rtl/ngage_mmc_card.v rtl/ngage_mmc_dpram.v rtl/ngage_board.v rtl/ngage_upp.v rtl/ngage_upp_peripherals.v rtl/ngage_upp_euart.v rtl/ngage_uem.v rtl/ngage_adsp.v rtl/ngage_lrb2.v rtl/ngage_mjoelner.v rtl/ngage_bram.v rtl/ngage_bram_be.v rtl/ngage_sparse_regs.v rtl/ngage_icu.v rtl/ngage_icu_extra.v rtl/ngage_timers.v rtl/ngage_nos_io.v rtl/ngage_mdi_stub.v rtl/ngage_upp_dsp_peer.v rtl/ngage_upp_mdi.v rtl/ngage_cbus_uem.v rtl/ngage_gpio_loopback.v rtl/ngage_boot_regs.v rtl/ngage_trace_sink.v tests/phone/system_probe/tb.v
for profile in current-boot simif-board; do
 g++ -std=c++17 -O2 -I"scratch/$profile/board" tests/phone/system_probe/reference.cpp "scratch/$profile/board/boot_profile.cpp" scratch/modem/ngage_modem.c -o "build/sim/unit-system-probe/$profile"
 "build/sim/unit-system-probe/$profile"
 vvp build/sim/unit-system-probe/test > "build/sim/unit-system-probe/$profile.log"
 grep -q '^PASS system-control' "build/sim/unit-system-probe/$profile.log"
 cat "build/sim/unit-system-probe/$profile.log"
done
