#!/usr/bin/env python3
"""Independent signed/unsigned/zero/random-addend math and changed-latency oracle."""
from pathlib import Path
import argparse,subprocess,json,random,hashlib
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('name');a=p.parse_args();out=ROOT/'build/sim/cpu-paired-delivery'/a.name;out.mkdir(parents=True,exist_ok=False)
(out/'result.json').write_text('{"status":"INCOMPLETE"}\n')
old=subprocess.check_output(['git','show','78d53d4:rtl/arm/zap_shifter_multiply.sv'],text=True).replace('module zap_shifter_multiply','module multiply_mapping_reference',1).replace('endmodule : zap_shifter_multiply','endmodule : multiply_mapping_reference');(out/'reference.sv').write_text(old)
rng=random.Random(0x35435052);mask=(1<<64)-1;edges=[0,1,2,0x7fff,0x8000,0xffff,0x10000,0x7fffffff,0x80000000,0xffffffff,0xfffffffe,0xffff0000,0x80010001,0x40000000];rows=[]
for n in range(2048):
 signed=n%2;a0=edges[(n//2)%len(edges)] if n<784 else rng.getrandbits(32);b0=edges[(n//28)%len(edges)] if n<784 else rng.getrandbits(32);acc=0 if n%4<2 else rng.getrandbits(64)
 sa=a0-(1<<32) if signed and a0>>31 else a0;sb=b0-(1<<32) if signed and b0>>31 else b0;expected=(sa*sb+acc)&mask;rows.append((signed<<192)|(a0<<160)|(b0<<128)|(acc<<64)|expected)
(out/'vectors.hex').write_text(''.join(f'{x:049x}\n' for x in rows))
s=(ROOT/'tests/cpu/multiply_mapping/tb.v').read_text().replace('  reg [195:0] vectors', '  wire hold_new = hold_data || hold_finished;\n  reg hold_finished=0;\n  integer old_ticks,new_ticks;\n  reg [195:0] vectors')
start=s.index('  zap_shifter_multiply production');end=s.index('  );',start);s=s[:start]+s[start:end].replace('.i_data_stall(hold_data)','.i_data_stall(hold_new)')+s[end:]
s=s.replace('build/sim/unit-multiply-mapping/vectors.hex',str((out/'vectors.hex').relative_to(ROOT)))
s=s.replace('if (old_busy !== new_busy) $fatal(1, "busy schedule differs vector%0d phase%0d", n, phase);','if (!cc && (old_busy || new_busy)) $fatal(1,"failed condition started operation");')
a0=s.index('        while (old_busy && step_count < 50)');b0=s.index('        check_busy();\n        if(old_busy',a0)
s=s[:a0]+'''        old_ticks=0; new_ticks=0; hold_finished=(!new_busy && old_busy);
        while ((old_busy || new_busy) && step_count < 50) begin
          rng = {rng[30:0], rng[31] ^ rng[21] ^ rng[1] ^ rng[0]};
          hold_data = rng[0] && rng[2];
          if (old_busy && !hold_data) old_ticks=old_ticks+1;
          if (new_busy && !hold_new) new_ticks=new_ticks+1;
          tick();
          if (!new_busy && old_busy) hold_finished=1;
          step_count=step_count+1;
        end
        if(old_ticks-new_ticks !== ((phase && n%4!=0) ? 2 : 0))
          $fatal(1,"unexpected latency class n%0d phase%0d old%0d new%0d",n,phase,old_ticks,new_ticks);
''' + s[b0:]
s=s.replace('    for (n = 0; n < 2048; n = n + 1) begin', '''
    // Exercise all six owned states using a nonzero addend, then each clear
    // priority. ALU clear defers under a data hold; WB clear/reset override it.
    for(integer stage_id=0;stage_id<6;stage_id=stage_id+1) begin
      for(integer kind=0;kind<3;kind=kind+1) begin
        reset=1;hold_data=0;hold_finished=0;cc=0;tick();reset=0;
        rm=3;rs=5;rn=1;rh=0;op=UMLALL;cc=1;
        repeat(stage_id)tick();
        hold_data=1;
        if(kind==0)begin
          kill_alu=1;
          begin
            reg[5:0] saved_state;
            saved_state=production.state_ff;tick();
            if(production.state_ff!==saved_state)$fatal(1,"held ALU kill escaped priority");
          end
          hold_data=0;tick();kill_alu=0;
        end else if(kind==1)begin kill_wb=1;tick();kill_wb=0;end
        else begin reset=1;tick();reset=0;end
        cc=0;hold_data=0;
        if(production.state_ff!==1 || old_unit.state_ff!==1)$fatal(1,"clear/reset failed in owned multiply state");
        tick();
      end
    end
    $display("PASS multiply cancellation/reset priorities:18 owned-stage cases");
    for (n = 0; n < 2048; n = n + 1) begin
''')
s=s.replace("        op = (vectors[n][192] ? SMLALL : UMLALL) + phase;","        if(phase && n%4==0) begin cc=0;op=MOV;tick();cc=1;end\n        op = (vectors[n][192] ? SMLALL : UMLALL) + phase;")
s=s.replace("      expected = vectors[n][63:0];","      expected = vectors[n][63:0] ^ ((n==0 && $test$plusargs(\"wrong_product\")) ? 64'd1 : 64'd0);")
s=s.replace('        hold_data = 0;\n        tick();\n        total', '        hold_data = 0; hold_finished=0;\n        tick();\n        total')
s=s.replace('unchanged busy under random holds','two high restart edges removed only for the immediate paired owner, old fallback after a bubble')
s=s.replace('production DSP multiply mapping','paired registered DSP delivery');(out/'tb.v').write_text(s)
cp=lambda p:'/work/'+str(p.relative_to(ROOT));docker=['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',str(ROOT)+':/work','-w','/work','--entrypoint']
files=[HERE/'rtl/arm/zap_shifter_multiply.sv',out/'reference.sv',out/'tb.v'];hashes={str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in files+[out/'vectors.hex']}
for cmd,log in [(docker+['verilator','jotego/simulator:arm64','--binary','--timing','--assert','-j','1','-Wno-fatal','-Wno-lint','-I/work/rtl/arm','--top-module','test','--Mdir',cp(out/'obj'),*[cp(f) for f in files]],'build.log'),(docker+[cp(out/'obj/Vtest'),'jotego/simulator:arm64'],'run.log')]:
 with (out/log).open('w') as f:r=subprocess.run(cmd,cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
 if r.returncode:raise RuntimeError(str(out/log))
text=(out/'run.log').read_text();assert 'PASS paired registered' in text
exe=out/'obj/Vtest';exe_sha=hashlib.sha256(exe.read_bytes()).hexdigest()
with (out/'repeat.log').open('w') as f:r=subprocess.run(docker+[cp(exe),'jotego/simulator:arm64'],cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
assert r.returncode==0
select=lambda s:[x for x in s.splitlines() if x.startswith('PASS')]
assert select(text)==select((out/'repeat.log').read_text())
with (out/'wrong-product.log').open('w') as f:r=subprocess.run(docker+[cp(exe),'jotego/simulator:arm64','+wrong_product'],cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
assert r.returncode!=0 and 'arithmetic/flags vector0' in (out/'wrong-product.log').read_text()
assert hashlib.sha256(exe.read_bytes()).hexdigest()==exe_sha
(out/'result.json').write_text(json.dumps(dict(status='PASS',source=hashes,zero_addend_vectors=1024,accumulating_vectors=1024,immediate_pairs=1536,expired_pairs=512,clear_reset_stage_cases=18,negative='EXPECTED_FAILURE wrong full product at vector0',executable_sha256=exe_sha,events=select(text)),indent=2)+'\n');print('\n'.join(select(text)));print('PASS exact repeats and wrong-product rejection')
