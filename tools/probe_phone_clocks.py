#!/usr/bin/env python3
"""Run the existing cold 5M-cycle smoke with read-only clock observations.

Uses the installed jotego/simulator:arm64 image and stock local firmware.
Generated sources stay under scratch; no RTL, firmware or checkpoint is edited.
"""
from pathlib import Path
import os
import subprocess

ROOT = Path(__file__).resolve().parents[1]
STAGE = Path('scratch/timing-closure/clock-research')
PROBE = r'''
 reg [31:0] clock_audit_cp15 = 32'hffffffff;
 integer clock_audit_writes = 0;
 always @(negedge clk) if (!reset) begin
  if (dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.u_zap_cp15_cb.r[1] !== clock_audit_cp15) begin
   clock_audit_cp15 = dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.u_zap_cp15_cb.r[1];
   $display("CLOCK_CP15 cycle=%0d fetch_pc=%h control=%h mode=%b", cycles,
    dut.board.upp.cpu_inside.cpu.u_zap.u_zap_core.o_instr_wb_adr, clock_audit_cp15, clock_audit_cp15[31:30]);
  end
 end
 always @(posedge clk) if(!reset && dut.wb_cyc && dut.wb_stb && dut.wb_ack && dut.wb_we && clock_audit_writes < 200) begin
  if ((dut.wb_adr >= 32'h08000000 && dut.wb_adr <= 32'h08000040) ||
      (dut.wb_adr >= 32'h0c120000 && dut.wb_adr <= 32'h0c120038) ||
      (dut.wb_adr >= 32'h0c149000 && dut.wb_adr < 32'h0c149010)) begin
   $display("CLOCK_WRITE cycle=%0d addr=%h sel=%h data=%h",cycles,dut.wb_adr,dut.wb_sel,dut.wb_dat_o);
   clock_audit_writes = clock_audit_writes + 1;
  end
 end
'''


def main():
    os.chdir(ROOT)
    STAGE.mkdir(parents=True, exist_ok=True)
    source = Path('tests/phone/hardware_boot/tb.v').read_text()
    boundary = source.rfind('endmodule')
    if boundary < 0:
        raise SystemExit('hardware boot testbench module boundary missing')
    (STAGE / 'clock-audit-tb.v').write_text(source[:boundary] + PROBE + source[boundary:])
    script = Path('tests/phone/hardware_boot/run.sh').read_text()
    old_tb = 'tests/phone/hardware_boot/tb.v'
    old_build = 'build/sim/unit-hardware-boot'
    if old_tb not in script or old_build not in script:
        raise SystemExit('hardware boot runner changed; review clock probe adaptation')
    script = script.replace(old_build, 'build/sim/unit-clock-audit')
    script = script.replace(old_tb, str(STAGE / 'clock-audit-tb.v'))
    script = script.replace('grep "^PASS bounded hardware-bound boot"',
                            'grep -E "^(CLOCK_|PASS bounded hardware-bound boot)"')
    runner = STAGE / 'run-clock-audit.sh'
    runner.write_text(script)
    log = STAGE / 'cold-5m-clock-audit.log'
    with log.open('w') as output:
        subprocess.run(['sh', str(runner)], stdout=output, stderr=subprocess.STDOUT, check=True)
    lines = log.read_text().splitlines()
    controls = sorted({line.split('control=')[1].split()[0]
                       for line in lines if line.startswith('CLOCK_CP15')})
    print('CP15 control values:', ', '.join(controls))
    print(next(line for line in lines if line.startswith('PASS bounded hardware-bound boot')))
    print('Clock register writes and CP15 transitions:', log)


if __name__ == '__main__':
    main()
