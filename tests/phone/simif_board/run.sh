#!/bin/sh
set -eu
mkdir -p build/sim/unit-simif-board
for card in 0 1; do
for present in 0 1; do
 extra=""
 if [ "$card" = 1 ]; then extra=rtl/ngage_test_sim.v; fi
 iverilog -g2005 -s tb -Ptb.PRESENT=$present -Ptb.TEST_CARD=$card -o build/sim/unit-simif-board/test rtl/ngage_simif.v $extra rtl/ngage_mmc_host.v rtl/ngage_mmc_card.v rtl/ngage_mmc_dpram.v rtl/ngage_board.v rtl/ngage_upp.v rtl/ngage_upp_peripherals.v rtl/ngage_uem.v rtl/ngage_adsp.v rtl/ngage_lrb2.v rtl/ngage_mjoelner.v rtl/ngage_bram.v rtl/ngage_bram_be.v rtl/ngage_sparse_regs.v rtl/ngage_icu.v rtl/ngage_icu_extra.v rtl/ngage_timers.v rtl/ngage_nos_io.v rtl/ngage_mdi_stub.v rtl/ngage_cbus_uem.v rtl/ngage_gpio_loopback.v rtl/ngage_boot_regs.v rtl/ngage_trace_sink.v tests/phone/simif_board/tb.v
 vvp build/sim/unit-simif-board/test > "build/sim/unit-simif-board/run-$card-$present.log"
 cat "build/sim/unit-simif-board/run-$card-$present.log"
 grep -q '^PASS board SIMIF' "build/sim/unit-simif-board/run-$card-$present.log"
done
done
