#!/bin/sh
# Run inside the existing offline simulator image. No phone boot or media.
set -eu
out=${CRT_OUT:-build/sim/unit-crt-output}
mkdir -p "$out"
python3 - "$out" "${CRT_SOURCE:-rtl/ngage_mister.v}" <<'PYCODE'
from pathlib import Path
import sys
source=Path(sys.argv[2]).read_text()
start=source.index('    reg [ 5:0] video_control')
end=source.index('    wire panic_trace',start)
ports="""module production_video_boundary (
 input wire clk_sys, raw_ce, raw_hsync, raw_vsync, raw_hblank, raw_vblank,
 input wire [11:0] raw_rgb,
 output wire ce_pix, hsync, vsync, hblank, vblank,
 output wire [11:0] rgb444
);
"""
Path(sys.argv[1],'production_boundary.v').write_text(ports+source[start:end]+'endmodule\n')
PYCODE
for divider in 12 16; do
 iverilog -g2012 -s tb -Ptb.PIXEL_DIV="$divider" -o "$out/test-$divider" \
  rtl/ngage_bram.v rtl/ngage_lcd_display.v "$out/production_boundary.v" \
  sys/scanlines.v sys/vga_out.sv tests/phone/crt_output/tb.v
 vvp "$out/test-$divider" > "$out/run-$divider.log" 2>&1
 cat "$out/run-$divider.log"
 grep -q '^PASS continuous CRT' "$out/run-$divider.log"
done
