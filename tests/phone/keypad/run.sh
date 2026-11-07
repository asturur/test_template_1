#!/bin/sh
set -eu
mkdir -p build/sim/unit-keypad
iverilog -g2005 -s tb -o build/sim/unit-keypad/test rtl/ngage_keys.v rtl/ngage_keypad.v tests/phone/keypad/tb.v
vvp build/sim/unit-keypad/test > build/sim/unit-keypad/run.log
cat build/sim/unit-keypad/run.log
grep -q '^PASS keypad' build/sim/unit-keypad/run.log
iverilog -g2005 -s tb -o build/sim/unit-keypad/board rtl/ngage_keypad.v rtl/ngage_board.v rtl/ngage_upp.v rtl/ngage_upp_peripherals.v rtl/ngage_uem.v rtl/ngage_adsp.v rtl/ngage_lrb2.v rtl/ngage_mjoelner.v rtl/ngage_bram_be.v rtl/ngage_sparse_regs.v rtl/ngage_icu.v rtl/ngage_icu_extra.v rtl/ngage_timers.v rtl/ngage_nos_io.v rtl/ngage_mdi_stub.v rtl/ngage_cbus_uem.v rtl/ngage_gpio_loopback.v rtl/ngage_boot_regs.v rtl/ngage_trace_sink.v tests/phone/keypad/board_tb.v
vvp build/sim/unit-keypad/board > build/sim/unit-keypad/board.log
cat build/sim/unit-keypad/board.log
grep -q '^PASS board keypad' build/sim/unit-keypad/board.log

iverilog -g2005 -s tb -o build/sim/unit-keypad/protocol rtl/ngage_keypad.v tests/phone/keypad/protocol_tb.v
vvp build/sim/unit-keypad/protocol > build/sim/unit-keypad/protocol.log
cat build/sim/unit-keypad/protocol.log
grep -q '^PASS keypad drive banks' build/sim/unit-keypad/protocol.log
