#!/usr/bin/env python3
"""The whole-board testbench (tests/phone/hardware_boot/tb.v) for membench.

Changes to the copy: the DDR3 port's first beat comes DDR_LAT clocks after a
read is accepted (parameter; the testbench's own figure is three), the flash
backing cache has the size of FLASH_CACHE (parameter), and the STI text
window is printed: the byte 0x01 as "[clock scalar-reads scalar-writes lines
ddr-reads ddr-lines]", the run ends at "#END". Also writes the SDRAM chip
model with the changes of run-real-sdram.sh and the guest's three images.

    bench_tb.py GUEST.bin SDRAM_MODEL.v OUTDIR
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
guest, model, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
out.mkdir(parents=True, exist_ok=True)

s = (ROOT / 'tests/phone/hardware_boot/tb.v').read_text()


def rep(old, new):
    global s
    if s.count(old) != 1:
        raise SystemExit(f'expected one occurrence of {old!r}')
    s = s.replace(old, new)


rep('parameter integer ROM_CACHE_BITS=64,ROM_CACHE_BYTES=1024;',
    'parameter integer ROM_CACHE_BITS=64,ROM_CACHE_BYTES=1024;\n'
    'parameter integer DDR_LAT=11;\nparameter integer FLASH_CACHE=32768;')
rep('reg [2:0] ddelay=0,sdelay=0;', 'reg [7:0] ddelay=0;reg [2:0] sdelay=0;')
rep('ddelay<=3;ddr_remaining<=ddr_burst;', 'ddelay<=DDR_LAT[7:0];ddr_remaining<=ddr_burst;')
rep('.FLASH_CACHE_BYTES(8192)', '.FLASH_CACHE_BYTES(FLASH_CACHE)')
rep(' reg [2047:0] core_path,extension_path,cdrive_path;',
    ''' reg [31:0] sti_tail=0;
 wire [7:0] sti_char = dut.board_trace_sel==1 ? dut.board_trace_data[7:0] :
   dut.board_trace_sel==2 ? dut.board_trace_data[15:8] :
   dut.board_trace_sel==4 ? dut.board_trace_data[23:16] : dut.board_trace_data[31:24];
 integer sdram_scalar_rd=0, sdram_scalar_wr=0, sdram_lines=0, ddr_reads=0, ddr_lines=0;
 always @(posedge clk) if(!reset) begin
  if(sack && !swe) sdram_scalar_rd<=sdram_scalar_rd+1;
  if(sack && swe) sdram_scalar_wr<=sdram_scalar_wr+1;
  if(ram_line_req && ram_line_ready && !lock) sdram_lines<=sdram_lines+1;
  if(pr && ddelay==0) ddr_reads<=ddr_reads+1;
  if(ddr_line && accept) ddr_lines<=ddr_lines+1;
  if(dut.board_trace_valid && dut.board_trace_addr>=32'h0de00000 && dut.board_trace_addr<32'h0de01000) begin
   if(sti_char==8'h01) $write("[%0d %0d %0d %0d %0d %0d]",cycles,sdram_scalar_rd,sdram_scalar_wr,sdram_lines,ddr_reads,ddr_lines);
   else if(sti_char!=8'h0d) $write("%c",sti_char);
   sti_tail<={sti_tail[23:0],sti_char};
   if({sti_tail[23:0],sti_char}=="#END") begin
    $display("");
    $display("BENCH_END cycles=%0d errors=%0d data_errors=%0d",cycles,errors,data_errors);
    $finish;
   end
  end
 end
 reg [2047:0] core_path,extension_path,cdrive_path;''')
(out / 'tb_bench.v').write_text(s)

m = model.read_text(encoding='latin-1')
old = "if (Dqm[0] === 1'bx || Dqm[1]== 1'bx) begin"
if m.count(old) != 1:
    raise SystemExit('unexpected SDRAM model')
m = m.replace(old, "if (1'b0) begin")
m = m.replace("Dq_dqm [ 7 : 0] = 8'bz;", "Dq_dqm [ 7 : 0] = 8'b0;")
m = m.replace("Dq_dqm [15 : 8] = 8'bz;", "Dq_dqm [15 : 8] = 8'b0;")
m = m.replace('downloading, VS, frame_cnt );', 'downloading, VS, frame_cnt, Dq_write );', 1)
m = m.replace('inout     [data_bits - 1 : 0] Dq;',
              'inout [data_bits - 1 : 0] Dq; input [data_bits - 1 : 0] Dq_write;', 1)
m = m.replace('= Dq [ 7 : 0];', '= Dq_write [ 7 : 0];').replace('= Dq [15 : 8];', '= Dq_write [15 : 8];')
(out / 'mt48lc16m16a2-verilator.v').write_text(m, encoding='latin-1')

# The guest is the flash image: ROM offsets from zero, then erased flash.
program = guest.read_bytes()
(out / 'core.bin').write_bytes(program + b'\xff' * (18612224 - len(program)))
(out / 'extension.bin').write_bytes(b'\xff' * 2293760)
(out / 'cdrive.img').write_bytes(b'\xff' * 4194304)
