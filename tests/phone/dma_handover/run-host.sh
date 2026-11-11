#!/bin/sh
set -eu
out=build/sim/unit-dma-handover
mkdir -p "$out"
iverilog -g2001 -s fence_tb -o "$out/fence" \
    rtl/ngage_dma_engine.v rtl/ngage_dma_channels.v rtl/ngage_lcd_stream.v tests/phone/dma_handover/fence_tb.v
vvp "$out/fence" > "$out/fence.log"
grep '^PASS' "$out/fence.log"
iverilog -g2001 -s fast_channels_tb -o "$out/fast-channels" \
    rtl/ngage_dma_engine.v rtl/ngage_dma_channels.v rtl/ngage_lcd_stream.v \
    tests/phone/dma_handover/fast_channels_tb.v
vvp "$out/fast-channels" > "$out/fast-channels.log"
grep '^PASS' "$out/fast-channels.log"
iverilog -g2001 -s transport_tb -o "$out/transport" \
    rtl/ngage_simif.v rtl/ngage_test_sim.v rtl/ngage_mmc_host.v rtl/ngage_mmc_card.v rtl/ngage_mmc_dpram.v rtl/ngage_board.v rtl/ngage_upp.v \
    rtl/ngage_upp_peripherals.v rtl/ngage_uem.v rtl/ngage_adsp.v rtl/ngage_lrb2.v \
    rtl/ngage_mjoelner.v rtl/ngage_bram.v rtl/ngage_bram_be.v rtl/ngage_sparse_regs.v \
    rtl/ngage_icu.v rtl/ngage_icu_extra.v rtl/ngage_timers.v rtl/ngage_nos_io.v \
    rtl/ngage_mdi_stub.v rtl/ngage_cbus_uem.v rtl/ngage_gpio_loopback.v \
    rtl/ngage_boot_regs.v rtl/ngage_trace_sink.v rtl/ngage_lcd_display.v \
    rtl/ngage_lcd_dma.v rtl/ngage_keypad.v rtl/ngage_dma_channels.v \
    rtl/ngage_dma_engine.v rtl/ngage_lcd_stream.v tests/phone/dma_handover/transport_tb.v
vvp "$out/transport" > "$out/transport.log"
grep '^PASS' "$out/transport.log"
