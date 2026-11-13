#!/bin/sh
set -eu
out=${PHONE_TEST_OUT:-build/sim/unit-keypad}
mkdir -p "$out"
iverilog -g2001 -s tb -o "$out"/test rtl/ngage_keys.v rtl/ngage_keypad.v tests/phone/keypad/tb.v
vvp "$out"/test > "$out"/run.log
cat "$out"/run.log
grep -q '^PASS keypad' "$out"/run.log
iverilog -g2001 -s tb -o "$out"/board rtl/ngage_keypad.v rtl/ngage_mmc_host.v rtl/ngage_mmc_card.v rtl/ngage_mmc_dpram.v rtl/ngage_board.v rtl/ngage_upp.v rtl/ngage_upp_peripherals.v rtl/ngage_upp_euart.v rtl/ngage_uem.v rtl/ngage_adsp.v rtl/ngage_lrb2.v rtl/ngage_mjoelner.v rtl/ngage_bram.v rtl/ngage_bram_be.v rtl/ngage_sparse_regs.v rtl/ngage_icu.v rtl/ngage_icu_extra.v rtl/ngage_timers.v rtl/ngage_nos_io.v rtl/ngage_mdi_stub.v rtl/ngage_upp_dsp_peer.v rtl/ngage_upp_mdi.v rtl/ngage_cbus_uem.v rtl/ngage_gpio_loopback.v rtl/ngage_boot_regs.v rtl/ngage_trace_sink.v tests/phone/keypad/board_tb.v
vvp "$out"/board > "$out"/board.log
cat "$out"/board.log
grep -q '^PASS board keypad' "$out"/board.log

iverilog -g2001 -s tb -o "$out"/protocol rtl/ngage_keypad.v tests/phone/keypad/protocol_tb.v
vvp "$out"/protocol > "$out"/protocol.log
cat "$out"/protocol.log
grep -q '^PASS keypad drive banks' "$out"/protocol.log
