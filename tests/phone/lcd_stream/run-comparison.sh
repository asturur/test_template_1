#!/bin/sh
set -eu
out=${LCD_STREAM_OUT:-build/sim/unit-lcd-stream}
mkdir -p "$out"
iverilog -g2001 -s comparison_tb -o "$out/comparison" rtl/ngage_lcd_stream.v rtl/ngage_lcd_dma.v rtl/ngage_sdram_arbiter.v tests/phone/lcd_stream/comparison_tb.v
if ! vvp "$out/comparison" > "$out/comparison.log"; then cat "$out/comparison.log"; exit 1; fi
cat "$out/comparison.log"
grep -q '^PASS LCD legacy/fast matched' "$out/comparison.log"
