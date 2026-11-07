#!/bin/sh
set -eu
out=build/sim/unit-debug-video
mkdir -p "$out"
python3 tools/generate_debug_font.py --check
iverilog -g2005 -E -DALTERA_RESERVED_QIS -o "$out/quartus-font.v" rtl/ngage_debug_font.v
python3 - "$out/quartus-font.v" <<'PY_CHECK'
from pathlib import Path
import re,sys
source=Path(sys.argv[1]).read_text()
assert 'altsyncram #' in source and 'rtl/ngage_debug_font.mif' in source
assert not re.search(r'reg\s+\[7:0\]\s+font',source)
print('PASS Quartus font path uses explicit initialized primitive')
PY_CHECK
iverilog -g2005 -s tb -o "$out/monitor" rtl/ngage_debug_monitor.v tests/phone/debug_video/monitor_tb.v
vvp "$out/monitor"
iverilog -g2005 -s tb -o "$out/video" rtl/ngage_debug_font.v rtl/ngage_debug_video.v tests/phone/debug_video/video_tb.v
vvp "$out/video"
python3 tests/phone/debug_video/check.py
