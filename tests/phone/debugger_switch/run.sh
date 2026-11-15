#!/bin/sh
set -eu
out=${PHONE_TEST_OUT:-build/sim/unit-debugger-switch}
mkdir -p "$out"
python3 - "$out" <<'PY'
import re,sys
from pathlib import Path
s=Path('Template.sv').read_text()
m=re.search(r'end else begin\s*:\s*loader_only\b(.*?)\n\s*end\s*\n\s*endgenerate',s,re.S)
assert m, 'loader-only production block changed'
ports='''module production_loader_only (
 input wire clk_sys,transport_reset,load_req,service_ready,service_done,
 input wire [31:0] load_addr,load_data,
 input wire [3:0] load_be,
 output wire service_valid,service_write,load_ready,load_done,
 output wire [31:0] service_addr,service_data,
 output wire [3:0] service_be
);
'''
Path(sys.argv[1],'loader.v').write_text(ports+m[1]+'\nendmodule\n')
PY
iverilog -g2001 -s tb -o "$out/test" rtl/ngage_diag_ddr.v "$out/loader.v" tests/phone/debugger_switch/tb.v
vvp "$out/test"
