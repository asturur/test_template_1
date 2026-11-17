#!/usr/bin/env python3
"""Assert a real IRQ during a long multiply; forbid partial destination pairs."""
from pathlib import Path
import argparse,json,hashlib,subprocess,shutil,re,os
ROOT=Path(__file__).resolve().parents[3]
p=argparse.ArgumentParser();p.add_argument('name');p.add_argument('--build',type=Path,required=True);a=p.parse_args();out=ROOT/'build/sim/cpu-paired-delivery'/a.name;out.mkdir(parents=True,exist_ok=False);build=ROOT/a.build
m=json.loads((build/'manifest.json').read_text());reference=out/'reference';reference.mkdir()
for name,h in m['source']['files'].items():assert hashlib.sha256((build/'source'/name).read_bytes()).hexdigest()==h,name
for directory in ['arm','arm920']:
 for f in (build/'source/rtl'/directory).iterdir():
  if f.is_file():shutil.copyfile(f,reference/f.name)
(out/'program.S').write_text('''.equ CUSTOM_IRQ,1
.include "sim/programs/common.inc"
reset_entry:
 mov r0,#7
 mvn r0,r0
 mov r1,#6
 ldr r2,=0x11223344
 ldr r3,=0x55667788
 mov r4,#0
 mrs r7,cpsr
 bic r7,r7,#0x80
 msr cpsr_c,r7
 smulls r2,r3,r0,r1
 mrs r8,cpsr
 mov r9,#200
1: cmp r4,#1
 beq 2f
 subs r9,r9,#1
 bne 1b
 b fail
2: cmn r2,#48
 bne fail
 cmn r3,#1
 bne fail
 and r8,r8,#0xc0000000
 cmp r8,#0x80000000
 bne fail
 // Signed accumulating fallback and independent unsigned zero-addend class.
 mov r2,#48
 mov r3,#0
 smlal r2,r3,r0,r1
 cmp r2,#0
 bne fail
 cmp r3,#0
 bne fail
 umull r2,r3,r0,r1
 cmn r2,#48
 bne fail
 cmp r3,#5
 bne fail
 // A failed condition must preserve both destinations.
 cmp r4,r4
 smullne r2,r3,r0,r1
 cmn r2,#48
 bne fail
 cmp r3,#5
 bne fail
 b pass
irq_handler:
 add r4,r4,#1
 ldr r10,=0x11223344
 cmp r2,r10
 bne committed_pair
 ldr r10,=0x55667788
 cmp r3,r10
 bne fail
 b return_irq
committed_pair:
 cmn r2,#48
 bne fail
 cmn r3,#1
 bne fail
return_irq:
 subs pc,lr,#4
fail: mov r0,#0xe9
 b finish
.ltorg
''')
rel=str(out.relative_to(ROOT));tb=(ROOT/'tests/cpu/core/test.sv').read_text().replace('build/sim/unit-core',rel).replace('module test;','''module test;
integer mul_irq_phase=0; integer mul_irq_state=4;
initial begin if($value$plusargs("mul_irq_state=%d",mul_irq_state))begin end end
always @(negedge clk) if(!reset) begin
 if(mul_irq_phase==0 && dut.u_zap.u_zap_core.u_zap_shifter_main.u_zap_multiply.state_ff==mul_irq_state)begin irq=1;mul_irq_phase=1;end
 if(mul_irq_phase==1 && dut.u_zap.cpu_cpsr[4:0]==5'h12)begin irq=0;mul_irq_phase=2;end
end
final begin if(mul_irq_phase!=2)$fatal(1,"multiply IRQ coverage missing");$display("PASS multiply IRQ state=%0d with whole low/high architectural pair",mul_irq_state);end
''',1);(out/'test.sv').write_text(tb)
s=(ROOT/'tests/cpu/core/sim.sh').read_text();s=re.sub(r'^root=.*$','root='+str(ROOT),s,flags=re.M);s=s.replace('build/sim/unit-core',rel).replace('tests/cpu/core/test.sv',rel+'/test.sv').replace('--rm --network none','--rm --pull=never --network none').replace('--binary --timing','--binary -j 1 --timing');(out/'run.sh').write_text(s)
with (out/'driver.log').open('w') as f:r=subprocess.run(['sh',str(out/'run.sh')],cwd=ROOT,env=dict(os.environ,CPU_PROGRAM='../../'+rel+'/program',CPU_REFERENCE_DIR=str(reference.relative_to(ROOT))),stdout=f,stderr=subprocess.STDOUT)
assert r.returncode==0,str(out/'driver.log')
# Reuse the exact existing5C guest and executable to assert IRQ in the
# new paired-ready owner too. No additional guest payload or build.
exe='/work/'+rel+'/Vtest'
for delay in [0,3]:
 with (out/f'pair-ready-{delay}.log').open('w') as f:
  r=subprocess.run(['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',str(ROOT)+':/work','-w','/work','--entrypoint',exe,'jotego/simulator:arm64','+ngage-compact-trace',f'+latency={delay}','+mul_irq_state=32'],cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
 assert r.returncode==0,str(out/f'pair-ready-{delay}.log')
for f in list(out.glob('run-*.log'))+list(out.glob('pair-ready-*.log')):assert 'PASS multiply IRQ' in f.read_text()
(out/'result.json').write_text(json.dumps(dict(status='PASS',source_id=m['source']['source_id'],irq_states=[4,32],logs={str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in list(out.glob('run-*.log'))+list(out.glob('pair-ready-*.log'))}),indent=2)+'\n');print('PASS real multiply IRQ, predication, flags, paired signed/unsigned and accumulating fallback at0/3waits')
