#!/bin/sh
# Diagnostic comparison against run.sh's Icarus/Micron test;
# Verilator has two-state wires and requires the controller's split DQ port.
set -eu
mkdir -p build/sim/milestone7
python3 - <<'PY'
from pathlib import Path
s=Path('scratch/sdram-reference/mt48lc16m16a2.v').read_text(encoding='latin-1')
old="if (Dqm[0] === 1'bx || Dqm[1]== 1'bx) begin"
assert s.count(old)==1
s=s.replace(old,"if (1'b0) begin")
# Verilator is two-state: Z on this temporary makes its procedural writes
# resolve as separate drivers and returns stale data. Masked read lanes have
# no valid value; choose zero only inside this test-only reference copy.
s=s.replace("Dq_dqm [ 7 : 0] = 8'bz;", "Dq_dqm [ 7 : 0] = 8'b0;")
s=s.replace("Dq_dqm [15 : 8] = 8'bz;", "Dq_dqm [15 : 8] = 8'b0;")
s=s.replace('downloading, VS, frame_cnt );','downloading, VS, frame_cnt, Dq_write );',1)
s=s.replace('inout     [data_bits - 1 : 0] Dq;','inout [data_bits - 1 : 0] Dq; input [data_bits - 1 : 0] Dq_write;',1)
s=s.replace('= Dq [ 7 : 0];','= Dq_write [ 7 : 0];').replace('= Dq [15 : 8];','= Dq_write [15 : 8];')
Path('build/sim/milestone7/sdram-model-verilator.v').write_text(s)
s=Path('tests/phone/sdram/tb.sv').read_text()
s=s.replace('parameter INVERTED_CLOCK=0, CAPTURE_NEGEDGE=0;', 'parameter INVERTED_CLOCK=1, CAPTURE_NEGEDGE=1;')
s=s.replace('tri [15:0] dq;', 'tri [15:0] dq; wire [15:0] dq_write; wire [15:0] dq_read=ram.Dq_reg;')
s=s.replace('.sdram_dq(dq),.sdram_a(a)', '.sdram_dq(dq_read),.sdram_din(dq_write),.sdram_a(a)')
s=s.replace('mt48lc16m16a2 ram(.Clk(memclk)', 'mt48lc16m16a2 ram(.Dq_write(dq_write),.Clk(memclk)')
Path('build/sim/milestone7/sdram-verilator-tb.sv').write_text(s)
PY
docker run --rm --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -c 'verilator --binary --timing --assert -Wno-fatal -Wno-lint --top-module tb --Mdir build/sim/milestone7/sdram-obj rtl/ngage_sdram_clock.v tests/phone/sdram/ddio_model.v rtl/ngage_sdram_adapter.v rtl/ngage_sdram_arbiter.v rtl/ngage_dma_route.v rtl/sdram/jtframe_sdram64*.v build/sim/milestone7/sdram-model-verilator.v build/sim/milestone7/sdram-verilator-tb.sv > build/sim/milestone7/sdram-build.log 2>&1 && build/sim/milestone7/sdram-obj/Vtb > build/sim/milestone7/sdram-verilator.log 2>&1'
