#!/bin/sh
set -eu
mkdir -p build/sim/unit-board-inventory
iverilog -g2005 -s tb -o build/sim/unit-board-inventory/test rtl/ngage_board.v rtl/ngage_bram_be.v rtl/ngage_sparse_regs.v rtl/ngage_icu.v rtl/ngage_icu_extra.v rtl/ngage_timers.v rtl/ngage_nos_io.v rtl/ngage_mdi_stub.v rtl/ngage_cbus_uem.v rtl/ngage_gpio_loopback.v rtl/ngage_boot_regs.v rtl/ngage_trace_sink.v tests/phone/board_inventory/tb.v
vvp build/sim/unit-board-inventory/test > build/sim/unit-board-inventory/run.log
cat build/sim/unit-board-inventory/run.log
grep -q '^PASS ownership' build/sim/unit-board-inventory/run.log
