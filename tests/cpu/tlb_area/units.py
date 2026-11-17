#!/usr/bin/env python3
"""Run original directed TLB coverage with explicit bank mutation drain."""
import argparse,json,subprocess,shutil,importlib.util,re,hashlib,sys
from pathlib import Path
from setup import ROOT,HERE,BASE,overlay
p=argparse.ArgumentParser();p.add_argument('--name',required=True);a=p.parse_args()
out=ROOT/'build/sim/tlb-area'/a.name;out.mkdir(parents=True,exist_ok=False)
sys.path.insert(0,str(ROOT/'tests/cpu/donor_import'))
spec=importlib.util.spec_from_file_location('area_support',ROOT/'tests/cpu/donor_import/run.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
b.snapshot(out/'source',BASE);overlay(out/'source',True);src=out/'source';manifest=b.source_manifest(src,BASE,'banked-TLB-area')
docker=['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',str(ROOT)+':/work','-w','/work','--entrypoint'];cp=lambda p:'/work/'+str(p.relative_to(ROOT))
def call(cmd,log):
    with (out/log).open('w') as f:r=subprocess.run(cmd,cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
    assert r.returncode==0,str(out/log)
call(docker+['iverilog','jotego/simulator:arm64','-g2001','-s','arm920_tlb_bank','-tnull',cp(src/'rtl/ngage_bram.v'),cp(src/'rtl/arm920/tlb_bank.sv')],'strict-verilog-2001.log')
results=[]
for name in ['tlb64_bank','tlb_attributes','tlb_lookup_owner','tlb_permission_reuse','tlb_two_mapping']:
    text=(ROOT/'tests/cpu'/name/'test.sv').read_text()
    if name=='tlb64_bank':
        text=text.replace('.fill(fill),',".cancel_fill(1'b0),.fill(fill),")
        text=text.replace('wire valid, hit;','wire busy;\n    wire valid, hit;').replace('.clk(clk),.reset(reset),.lookup(lookup)', '.clk(clk),.busy(busy),.reset(reset),.lookup(lookup)')
        text=text.replace('fill=0;tick();end','fill=0;while(busy)tick();tick();end')
        text=text.replace('lookup=0;tick();\n            if (!valid', 'lookup=0;while(!valid)tick();\n            if (!valid')
        # All/MVA invalidation is now explicit serial maintenance.
        text=text.replace('inv=0;tick();','inv=0;while(busy)tick();tick();')
    else:
        # Controller o_busy already contains the bank scan, so settle helpers
        # naturally wait. CP15-like standalone commands must allow it to drain.
        pass
    # Passive totals include setup/mutations; no guest or permission oracle edit.
    prefix='dut' if name=='tlb64_bank' else 'dut.bank'
    text=text.replace('module test;',f'''module test;
integer searches=0,fills=0,invalidates=0,locks=0,busy_clocks=0;
always @(posedge clk)if(!reset)begin
    if({prefix}.lookup)searches=searches+1;
    if({prefix}.fill)fills=fills+1;
    if({prefix}.invalidate)invalidates=invalidates+1;
    if({prefix}.lock_write)locks=locks+1;
    if({prefix}.busy)busy_clocks=busy_clocks+1;
end
final $display("AREA_UNIT searches=%0d fills=%0d invalidates=%0d locks=%0d busy=%0d",searches,fills,invalidates,locks,busy_clocks);
''',1)
    (out/(name+'.sv')).write_text(text)
    files=[src/'rtl/ngage_bram.v',src/'rtl/arm920/tlb_bank.sv']+([] if name=='tlb64_bank' else [src/'rtl/arm920/tlb.sv'])+[out/(name+'.sv')]
    call(docker+['verilator','jotego/simulator:arm64','--binary','--timing','--assert','-j','1','-Wno-fatal','-Wno-lint','--top-module','test','--Mdir',cp(out/('obj-'+name))]+[cp(f) for f in files],name+'-build.log')
    call(docker+[cp(out/('obj-'+name)/'Vtest'),'jotego/simulator:arm64'],name+'.log')
    log=(out/(name+'.log')).read_text();assert 'PASS' in log
    results.append(dict(case=name,events=[l for l in log.splitlines() if l.startswith(('PASS','AREA_UNIT'))]));print(name,results[-1]['events'],flush=True)
(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');(out/'result.json').write_text(json.dumps(dict(status='PASS',strict_verilog_2001=True,source=manifest,rows=results),indent=2)+'\n')
