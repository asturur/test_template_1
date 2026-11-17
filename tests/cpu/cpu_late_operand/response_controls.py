#!/usr/bin/env python3
"""Bounded missing-response hold and one-shot retry at the CPU response boundary."""
import json,shutil,argparse,re
from pathlib import Path
from bench import ROOT,IMAGE,cp,call,save,sha
p=argparse.ArgumentParser();p.add_argument('--build',type=Path,required=True);p.add_argument('--name',default='step5l-response-01');a=p.parse_args()
assert re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,63}',a.name)
build=ROOT/a.build;out=ROOT/'build/sim/cpu-late-operand'/a.name;out.mkdir(exist_ok=False)
m=json.loads((build/'manifest.json').read_text());safety=json.loads((build/'safety.json').read_text())
loadpc=safety['symbols']['late_cold_load'];consumer=safety['symbols']['late_cold_consumer']
s=(build/'tb.v').read_text()
extra=f'''
integer response_mode=0, response_accepted=0, response_picked=0, response_executed=0;
integer response_start=-1, response_retries=0;
reg response_retry=0;
initial begin
    if(!$value$plusargs("response_mode=%d",response_mode))response_mode=0;
    force dut.u_zap.u_zap_core.i_dcache_err2=response_retry;
end
// Inject only a registered retry indication on the exact acknowledged load.
// This test does not claim to validate the cache's own retry-generation policy.
always @(negedge clk) begin
    response_retry=response_mode==2 && response_retries==0 &&
        dut.u_zap.u_zap_core.completion_offer && dut.u_zap.u_zap_core.i_data_wb_ack &&
        dut.u_zap.u_zap_core.postalu_pc_plus_8_ff==32'h{loadpc+8:08x};
end
always @(posedge clk) begin
    if(!reset) begin
        if(response_retry)response_retries=response_retries+1;
        if(dut.u_zap.u_zap_core.u_zap_issue_main.operand_pop &&
           dut.u_zap.u_zap_core.u_zap_issue_main.late_eligible &&
           dut.u_zap.u_zap_core.u_zap_issue_main.operand_pc_plus_8_ff==32'h{consumer+8:08x})begin
            response_accepted=response_accepted+1;
            if(response_start<0)response_start=cycles;
        end
        if(dut.u_zap.u_zap_core.alu_dav_ff && !dut.u_zap.u_zap_core.data_stall &&
           dut.u_zap.u_zap_core.alu_pc_plus_8_ff==32'h{consumer+8:08x})response_executed=response_executed+1;
        if(response_mode==1 && response_start>=0)begin
            if(cycles-response_start>2 && (!dut.u_zap.u_zap_core.data_stall ||
               !dut.u_zap.u_zap_core.issue_late_rn ||
               dut.u_zap.u_zap_core.issue_pc_plus_8_ff!=32'h{consumer+8:08x} ||
               dut.u_zap.u_zap_core.completion_valid || response_executed!=0))
                $fatal(1,"missing-response dependent escaped hold");
            if(cycles-response_start==128)begin
                $display("RESPONSE_HOLD_PASS clocks=128 accepted=%0d executed=%0d",response_accepted,response_executed);
                $finish;
            end
        end
        if(retire && retire_pc==32'h{consumer:08x} && response_mode==2)begin
            if(response_retries!=1 || response_accepted<2 || response_executed!=1)
                $fatal(1,"retry did not kill/replay dependent exactly once");
            $display("RESPONSE_RETRY_PASS retries=%0d accepted=%0d executed=%0d",response_retries,response_accepted,response_executed);
        end
    end
end
'''
s=s.replace('module bench;','module bench;\n'+extra,1)
# Block the external line response for this particular cold demand only.
s=s.replace('if(line_wait>0)line_wait<=line_wait-1;',f'if(response_mode==1 && response_start>=0)line_wait<=1000000;\n                else if(line_wait>0)line_wait<=line_wait-1;')
(out/'tb.v').write_text(s)
for f in ['span.vh','observe.vh']:shutil.copyfile(build/f,out/f)
docker=['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',str(ROOT)+':/work','-w','/work','--entrypoint']
rtl=[build/'source/rtl/ngage_cpu.sv',build/'source/rtl/ngage_bram.v']
for d in ['arm','arm920']:rtl+=sorted(p for p in (build/'source/rtl'/d).iterdir() if p.suffix in ['.v','.sv'])
call(docker+['verilator',IMAGE,'--binary','--timing','--assert','-j','1','-Wno-fatal','-Wno-lint','-DNGAGE_RUNTIME_TRACE','-DBENCH_HAS_LINE','-DPIPE_P1','-DLOOKUP_PROBE','-GLINE_ENABLE=1','--top-module','bench','--Mdir',cp(out/'obj'),'-I'+cp(out),'-I'+cp(build/'source/rtl/arm')]+[cp(p) for p in rtl]+[cp(out/'tb.v')],out/'build.log')
rows=[]
for mode,marker in [(1,'RESPONSE_HOLD_PASS'),(2,'RESPONSE_RETRY_PASS')]:
    log=out/f'mode-{mode}.log'
    call(docker+[cp(out/'obj/Vbench'),IMAGE,'+program='+cp(build/'safety.hex'),'+payload='+cp(build/'empty.hex'),'+firmware='+cp(build/'empty.hex'),'+begin_pc=1','+end_pc=2','+inject_irq=1','+max_cycles=3000000',f'+response_mode={mode}'],log)
    text=log.read_text();assert marker in text
    rows.append(dict(mode=mode,evidence=[l for l in text.splitlines() if l.startswith(marker)]))
save(out/'result.json',dict(status='PASS',source=m['source'],harness_sha256=sha(out/'tb.v'),executable_sha256=sha(out/'obj/Vbench'),rows=rows))
print('PASS bounded missing response and injected retry cancellation/replay')
