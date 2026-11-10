#!/bin/sh
set -eu
mkdir -p build/sim/unit-diag-export
iverilog -g2005 -s tb -o build/sim/unit-diag-export/test rtl/ngage_diag_export.v rtl/ngage_bram.v rtl/ngage_sd_sector.sv tests/phone/diag_export/tb.v
vvp build/sim/unit-diag-export/test > build/sim/unit-diag-export/run.log
cat build/sim/unit-diag-export/run.log
grep -q '^PASS diagnostic snapshot' build/sim/unit-diag-export/run.log
iverilog -g2005 -s tb -o build/sim/unit-diag-export/integrated rtl/ngage_diagnostics.v rtl/ngage_diag_export.v rtl/ngage_bram.v rtl/ngage_sd_sector.sv tests/phone/diag_export/integrated.v
vvp build/sim/unit-diag-export/integrated > build/sim/unit-diag-export/integrated.log
cat build/sim/unit-diag-export/integrated.log
grep -q '^PASS diagnostic ring' build/sim/unit-diag-export/integrated.log
python3 tools/ngage_diagnostics.py decode build/sim/unit-diag-export/captured.ngd > build/sim/unit-diag-export/captured.json
python3 - <<'PY'
import json
v=json.load(open('build/sim/unit-diag-export/captured.json'))
assert v['fault_address']=='0x12345678' and v['fault_reason']==2 and v['fault_seen']
assert [x['data'] for x in v['events']]==['0x41424340','0x41424341','0x41424342','0x65637845','0x6f697470','0x00010003']
assert v['dropped_events']==2
assert v['save_errors']=={'C:':False,'PMM':True}
assert v['panic_report']=={'valid_mask':7,'category_hex':'457863657074696f','category':'Exceptio','reason':0x10003}
print('PASS decoded exported fault, events and dropped count')
PY
# Test-only adaptation: legacy hps_io references PS/2 generate-block members
# without scope; make that scope explicit for Verilator. SD logic is unchanged.
python3 - <<'PYHPS'
from pathlib import Path
import re
s=Path('sys/hps_io.sv').read_text()
a,b=s.split('///////////////////////////////   PS2   ///////////////////////////////',1)
names='kbd_rd kbd_we kbd_data kbd_data_host mouse_rd mouse_we mouse_data mouse_data_host'.split()
for name in names:a=re.sub(r'(?<![\w.])'+name+r'\b','ps2_model.'+name,a)
b=b.replace('if(PS2DIV) begin','if(PS2DIV) begin: ps2_model',1)
Path('build/sim/unit-diag-export/hps-compat.sv').write_text(a+'///////////////////////////////   PS2   ///////////////////////////////'+b)
PYHPS
verilator --binary --timing -Wno-fatal -Wno-lint --top-module tb --Mdir build/sim/unit-diag-export/hps-obj build/sim/unit-diag-export/hps-compat.sv rtl/ngage_diag_export.v rtl/ngage_bram.v rtl/ngage_sd_sector.sv tests/phone/diag_export/hps_tb.sv > build/sim/unit-diag-export/hps-build.log 2>&1
build/sim/unit-diag-export/hps-obj/Vtb > build/sim/unit-diag-export/hps.log
cat build/sim/unit-diag-export/hps.log
grep -q '^PASS diagnostic export through real hps_io' build/sim/unit-diag-export/hps.log
