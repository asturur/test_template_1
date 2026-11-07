#!/bin/sh
set -eu
out=build/sim/unit-lcd-native
mkdir -p "$out"
iverilog -g2005 -s tb -o "$out/test" rtl/ngage_bram.v rtl/ngage_lcd_display.v tests/phone/lcd_display/native_tb.v
vvp "$out/test" > "$out/run.log"
cat "$out/run.log"
grep -q '^PASS native 176x208' "$out/run.log"
# This is an explicit display-only replay of an observed firmware frame,
# separate from the cold phone boot and with no CPU or firmware mutation.
if [ -f build/sim/runs/logo-normal-2000m/framebuffer.bin ]; then
 python3 - <<'PY'
from pathlib import Path
import hashlib,struct
p=Path('build/sim/runs/logo-normal-2000m/framebuffer.bin');b=p.read_bytes()
assert hashlib.sha256(b).hexdigest()=='aa346d99a4db8515e4e7500c93d58ea329dee8c94cea543a26efed120b979737'
Path('build/sim/unit-lcd-native/logo.hex').write_text(''.join(f'{w:08x}\n' for w, in struct.iter_unpack('<I',b)))
PY
 vvp "$out/test" +FRAME="$out/logo.hex" +PPM="$out/scanout.ppm" > "$out/replay.log"
 cat "$out/replay.log"
 python3 - <<'PY'
from pathlib import Path
import runpy,hashlib,json
out=Path('build/sim/unit-lcd-native');screens=Path('build/sim/screens/native-phone-video-replay');screens.mkdir(exist_ok=True)
runpy.run_path('tests/phone/hardware_boot/run-logo.py')['png'](out/'scanout.ppm',screens/'scanout.png')
# Every output RGB byte must match the observed source framebuffer PNG.
old=Path('build/sim/screens/logo-normal-2000m/framebuffer.png')
assert (screens/'scanout.png').read_bytes()==old.read_bytes()
(screens/'provenance.json').write_text(json.dumps({'kind':'display-only RTL replay, not a new phone cold boot','source':'build/sim/runs/logo-normal-2000m/framebuffer.bin','active_resolution':[176,208],'scanout_png_sha256':hashlib.sha256((screens/'scanout.png').read_bytes()).hexdigest(),'result':'All active raster pixels exactly match the observed firmware frame; no padding or diagnostic overlay.'},indent=2)+'\n')
print('PASS native scanout matches saved firmware frame pixel-for-pixel')
PY
fi
