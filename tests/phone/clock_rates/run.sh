#!/bin/sh
# Run inside the existing jotego/simulator:arm64 image.
set -eu
out=${PHONE_TEST_OUT:-build/sim/unit-clock-rates}
mkdir -p "$out"
python3 - <<'PY'
from pathlib import Path
s=''.join(Path('Template.sv').read_text().split());p=Path('rtl/pll/pll_0002.v').read_text()
assert 'SYS_CLK_HZ=104000000' in s
assert p.count('104.000000 MHz')==2 and '.phase_shift1("-2404ps")' in ''.join(p.split())
assert '.SD_TIMEOUT(SYS_CLK_HZ)' in s
assert '.SYS_CLK_HZ(SYS_CLK_HZ)' in s and '.outclk_1()' in s
assert 'MMC_CLK_DIV=3;' in s and '.MMC_CLK_DIV(MMC_CLK_DIV)' in s
assert 'assignVGA_HS=core_hsync;' in s and 'assignVGA_VS=core_vsync;' in s
assert '.TIMER_CLK_DIV(SYS_CLK_HZ/26000000)' in s and '.NOS_TICK_HZ(64)' in s
assert 'ngage_sdram_clock' in s and '.sdram_clk(SDRAM_CLK)' in s
assert '.CLK_HZ(SYS_CLK_HZ)' in s
print('PASS physical 104 MHz PLL, DDIO, integer MMC, 64 Hz timers and source raster selection')
PY
iverilog -g2012 -s tb -o "$out/test" rtl/ngage_simif.v rtl/ngage_test_sim.v rtl/ngage_mmc_host.v rtl/ngage_mmc_card.v rtl/ngage_mmc_dpram.v rtl/ngage_board.v rtl/ngage_upp.v rtl/ngage_upp_peripherals.v rtl/ngage_upp_euart.v rtl/ngage_uem.v rtl/ngage_adsp.v rtl/ngage_adsp_bootstrap_tx.v rtl/ngage_adsp_diagnostic.v rtl/ngage_aic23.v rtl/ngage_lrb2.v rtl/ngage_mjoelner.v rtl/ngage_bram.v rtl/ngage_bram_be.v rtl/ngage_sparse_regs.v rtl/ngage_icu.v rtl/ngage_icu_extra.v rtl/ngage_timers.v rtl/ngage_nos_io.v rtl/ngage_mdi_stub.v rtl/ngage_upp_dsp_peer.v rtl/ngage_upp_mdi.v rtl/ngage_cbus_uem.v rtl/ngage_gpio_loopback.v rtl/ngage_boot_regs.v rtl/ngage_trace_sink.v rtl/ngage_lcd_display.v rtl/ngage_sdram_adapter.v tests/phone/clock_rates/tb.sv
vvp "$out/test"

for config in '104000000 16' '78000000 12'; do
 set -- $config
 iverilog -g2005 -s tb -Ptb.SYS_HZ="$1" -Ptb.PIXEL_DIV="$2" \
    -o "$out/video" rtl/ngage_bram.v rtl/ngage_lcd_display.v tests/phone/lcd_display/native_tb.v
 vvp "$out/video" > "$out/video-$2.log"
 cat "$out/video-$2.log"
 grep '^PASS native ' "$out/video-$2.log" > "$out/raster-$2.txt"
done
cmp "$out/raster-16.txt" "$out/raster-12.txt"
