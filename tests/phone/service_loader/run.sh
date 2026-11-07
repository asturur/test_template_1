#!/bin/sh
# Inside the existing jotego/simulator:arm64 image; no firmware is rewritten.
set -eu
mkdir -p build/sim/service-loader
python3 tools/service_firmware.py > build/sim/service-loader/oracle.json
python3 tests/phone/service_loader/oracle_test.py
python3 - <<'PY'
from pathlib import Path
import re
s=Path('sys/hps_io.sv').read_text()
a,b=s.split('///////////////////////////////   PS2   ///////////////////////////////',1)
for name in 'kbd_rd kbd_we kbd_data kbd_data_host mouse_rd mouse_we mouse_data mouse_data_host'.split():
 a=re.sub(r'(?<![\w.])'+name+r'\b','ps2_model.'+name,a)
b=b.replace('if(PS2DIV) begin','if(PS2DIV) begin: ps2_model',1)
Path('build/sim/service-loader/hps-compat.sv').write_text(a+'///////////////////////////////   PS2   ///////////////////////////////'+b)
PY
verilator --cc --exe --build -j 2 -Wno-fatal --top-module service_transport \
 --Mdir build/sim/service-loader/obj \
 build/sim/service-loader/hps-compat.sv rtl/ngage_bundle_gate.v rtl/ngage_service_loader.v \
 rtl/ngage_ddr_adapter.sv rtl/ngage_ddr_lanes.sv rtl/ngage_descramble.v rtl/ngage_flash_read_decode.v \
 tests/phone/service_loader/transport.v /work/tests/phone/service_loader/test.cpp \
 > build/sim/service-loader/build.log 2>&1
build/sim/service-loader/obj/Vservice_transport
