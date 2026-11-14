#!/bin/sh
set -eu
out=build/sim/unit-mmc-production
mkdir -p "$out"
common='rtl/ngage_upp_peripherals.v rtl/ngage_upp_euart.v rtl/ngage_mmc_host.v rtl/ngage_simif.v rtl/ngage_bram.v rtl/ngage_bram_be.v rtl/ngage_sparse_regs.v rtl/ngage_icu.v rtl/ngage_icu_extra.v rtl/ngage_timers.v rtl/ngage_nos_io.v rtl/ngage_gpio_loopback.v rtl/ngage_boot_regs.v rtl/ngage_trace_sink.v rtl/ngage_keypad.v'
iverilog -g2001 -s tb -o "$out/bus" $common tests/phone/mmc_production/bus_tb.v > "$out/bus-build.log" 2>&1
vvp "$out/bus" > "$out/bus.log" 2>&1
grep '^PASS' "$out/bus.log"
for rx_control in 2 3; do
    iverilog -g2001 -s tb -Ptb.RX_CONTROL="$rx_control" -o "$out/dma-$rx_control" $common rtl/ngage_upp.v rtl/ngage_dma_channels.v rtl/ngage_dma_engine.v rtl/ngage_dma_route.v rtl/ngage_lcd_stream.v tests/phone/mmc_production/cpu_peer.v tests/phone/mmc_production/dma_tb.v > "$out/dma-$rx_control-build.log" 2>&1
    vvp "$out/dma-$rx_control" > "$out/dma-$rx_control.log" 2>&1
    grep '^PASS' "$out/dma-$rx_control.log"
done
