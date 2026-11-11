#!/bin/sh
set -eu
out=${LCD_STREAM_OUT:-build/sim/unit-lcd-stream}
mkdir -p "$out"
for mode in direct native; do
    define=
    if [ "$mode" = native ]; then define=-DNATIVE_ARBITER; fi
    iverilog -g2001 $define -s tb -o "$out/$mode" rtl/ngage_lcd_stream.v rtl/ngage_sdram_arbiter.v tests/phone/lcd_stream/tb.v
    if ! vvp "$out/$mode" > "$out/$mode.log"; then cat "$out/$mode.log"; exit 1; fi
    cat "$out/$mode.log"
    grep -q '^PASS LCD stream' "$out/$mode.log"
done
