#!/bin/sh
# Run inside the existing jotego/simulator:arm64 image.
set -eu
out=build/sim/unit-clock-rates
mkdir -p "$out"
python3 - <<'PY'
from pathlib import Path
s=Path('Template.sv').read_text();p=Path('rtl/pll/pll_0002.v').read_text()
assert 'SYS_CLK_HZ = 78000000' in s
assert p.count('78.000000 MHz')==2 and '.phase_shift1("-3205 ps")' in p
assert '.SD_TIMEOUT(SYS_CLK_HZ)' in s and '.TIMEOUT(SYS_CLK_HZ)' in s
assert '.SYS_CLK_HZ(SYS_CLK_HZ)' in ''.join(s.split()) and '.outclk_1()' in s
assert '.HF                  (1)' in s and '.READ_CAPTURE_NEGEDGE(1)' in s
assert "(64'd6800 * SYS_CLK_HZ) / 104000000" in s
print('PASS hardware78MHz PLL, HF1/DDIO, refresh and timeout selection')
PY
iverilog -g2012 -s tb -o "$out/test" rtl/ngage_simif.v rtl/ngage_test_sim.v rtl/ngage_board.v rtl/ngage_upp.v rtl/ngage_upp_peripherals.v rtl/ngage_uem.v rtl/ngage_adsp.v rtl/ngage_lrb2.v rtl/ngage_mjoelner.v rtl/ngage_bram.v rtl/ngage_bram_be.v rtl/ngage_sparse_regs.v rtl/ngage_icu.v rtl/ngage_icu_extra.v rtl/ngage_timers.v rtl/ngage_nos_io.v rtl/ngage_mdi_stub.v rtl/ngage_cbus_uem.v rtl/ngage_gpio_loopback.v rtl/ngage_boot_regs.v rtl/ngage_trace_sink.v rtl/ngage_lcd_display.v rtl/ngage_sdram_adapter.v tests/phone/clock_rates/tb.sv
vvp "$out/test"

for divider in 16 12; do
 iverilog -g2005 -s tb -Ptb.PIXEL_DIV="$divider" -o "$out/video" rtl/ngage_bram.v rtl/ngage_lcd_display.v tests/phone/lcd_display/native_tb.v
 vvp "$out/video" > "$out/video-$divider.log"
 cat "$out/video-$divider.log"
done
