#!/bin/sh
# Inside the existing simulator image. Arguments: NGO pack, raw core, extension.
set -eu
cache=${FLASH_CACHE_BYTES:-0}
out=build/sim/unit-overlay-hps
if [ "$cache" != 0 ]; then out="$out-cache-$cache"; fi
mkdir -p "$out"
python3 - "$out" <<'PY'
from pathlib import Path
import re,sys
s=Path('sys/hps_io.sv').read_text()
a,b=s.split('///////////////////////////////   PS2   ///////////////////////////////',1)
for name in 'kbd_rd kbd_we kbd_data kbd_data_host mouse_rd mouse_we mouse_data mouse_data_host'.split():
 a=re.sub(r'(?<![\w.])'+name+r'\b','ps2_model.'+name,a)
b=b.replace('if(PS2DIV) begin','if(PS2DIV) begin: ps2_model',1)
(Path(sys.argv[1])/'hps-compat.sv').write_text(a+'///////////////////////////////   PS2   ///////////////////////////////'+b)
PY
verilator --cc --exe --build -j 2 -Wno-fatal --top-module overlay_transport -GFLASH_CACHE_BYTES="$cache" \
 --Mdir "$out/obj" "$out/hps-compat.sv" rtl/ngage_bram.v rtl/ngage_nos_overlay.v \
 rtl/ngage_ddr_arbiter.v rtl/ngage_ddr_adapter.v rtl/ngage_ddr_lanes.sv \
 rtl/ngage_ddr_stream.v rtl/ngage_ddr_stream_legacy.v rtl/ngage_ddr_flash_cache.v rtl/ngage_ddr_flash_adapter.v \
 tests/phone/overlay/hps_transport.v /work/tests/phone/overlay/hps_test.cpp \
 > "$out/build.log" 2>&1
"$out/obj/Voverlay_transport" "$@"
