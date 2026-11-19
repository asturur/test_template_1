#!/bin/sh
# ngage_sdram_fast against the SDRAM chip model at 78 and 104 MHz. Run from
# the repository root with Verilator 5 on the path (or inside the simulator
# image). PHONE_SDRAM_MODEL is the mt48lc16m16a2.v of the other SDRAM tests.
set -eu
out=build/sim/unit-sdram-fast
mkdir -p "$out"
python3 - "$out" <<'PYMODEL'
import os
import sys
from pathlib import Path
p = Path(os.environ.get('PHONE_SDRAM_MODEL', 'scratch/sdram-reference/mt48lc16m16a2.v'))
s = p.read_text(encoding='latin-1')
old = "if (Dqm[0] === 1'bx || Dqm[1]== 1'bx) begin"
assert s.count(old) == 1
s = s.replace(old, "if (1'b0) begin")
s = s.replace("Dq_dqm [ 7 : 0] = 8'bz;", "Dq_dqm [ 7 : 0] = 8'b0;")
s = s.replace("Dq_dqm [15 : 8] = 8'bz;", "Dq_dqm [15 : 8] = 8'b0;")
s = s.replace('downloading, VS, frame_cnt );', 'downloading, VS, frame_cnt, Dq_write );', 1)
s = s.replace('inout     [data_bits - 1 : 0] Dq;', 'inout [data_bits - 1 : 0] Dq; input [data_bits - 1 : 0] Dq_write;', 1)
s = s.replace('= Dq [ 7 : 0];', '= Dq_write [ 7 : 0];').replace('= Dq [15 : 8];', '= Dq_write [15 : 8];')
Path(sys.argv[1], 'mt48lc16m16a2-verilator.v').write_text(s, encoding='latin-1')
PYMODEL
for hz in 78000000 104000000; do
    verilator --binary --timing --assert -j 4 -Wno-fatal -Wno-lint -GSYS_CLK_HZ=$hz --top-module tb \
        --Mdir "$out/obj-$hz" rtl/ngage_sdram_fast.v rtl/sdram/ngage2_sdram.sv rtl/ngage_sdram_clock.v \
        tests/phone/sdram/ddio_model.v "$out/mt48lc16m16a2-verilator.v" tests/phone/sdram_fast/tb.v > "$out/build-$hz.log" 2>&1
    "$out/obj-$hz/Vtb" > "$out/run-$hz.log" 2>&1 || { tail -20 "$out/run-$hz.log"; exit 1; }
    if grep -i -E 'violation|invalid|illegal' "$out/run-$hz.log"; then exit 1; fi
    grep '^PASS' "$out/run-$hz.log"
done
