#!/usr/bin/env python3
"""Freeze Stop 3C or the explicit Step 4A overlay; run a real ARM store loop."""
from pathlib import Path
import argparse,hashlib,json,subprocess,sys,importlib.util,shutil
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('name');p.add_argument('--control',action='store_true');p.add_argument('--reuse',type=Path);p.add_argument('--arg',action='append',default=[]);a=p.parse_args()
out=ROOT/'build/sim/cpu-store-overlap'/a.name;out.mkdir(parents=True,exist_ok=False)
(out/'result.json').write_text(json.dumps(dict(status='INCOMPLETE'))+'\n')
qualified=json.loads((ROOT/'docs/evidence/cache-probe-admission-retime-20261116.json').read_text())
for name,value in qualified['rtl_sha256'].items():assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==value,name
sys.path.insert(0,str(ROOT/'tests/cpu/spmark_payload'))
from workloads import assembly,cases
sys.path.insert(0,str(ROOT/'tests/cpu/donor_import'))
spec=importlib.util.spec_from_file_location('support',ROOT/'tests/cpu/donor_import/run.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
source=out/'source';base=b.snapshot(source,'9c948da8da413a882e0fe8e559c380ea0cadabf4',ROOT)
for f in (ROOT/'tests/cpu/cache_probe_retime/rtl').glob('cache*.sv'):shutil.copyfile(f,source/'rtl/arm920'/f.name)
if not a.control:
 for f in (HERE/'rtl').rglob('*'):
  if f.is_file():shutil.copyfile(f,source/'rtl'/f.relative_to(HERE/'rtl'))
base=b.source_manifest(source,base['commit'],'cpu-store-overlap-control' if a.control else 'cpu-store-overlap-candidate')
prefix=assembly(cases()[1]).split(' mov r11,#')[0]
prefix=prefix.replace(' .rept 7\n b fail\n .endr',' b fail\n b fail\n b fail\n b abort_handler\n b fail\n b irq_handler\n b fail')
program=prefix+'''
 ldr r10,=0x80001000
 ldr r1,=0x11111111
 ldr r2,=0x22222222
 ldr r3,=0x33333333
 ldr r4,=0x44444444
 ldr r0,[r10]
 ldr r0,[r10,#32]
 ldr r0,[r10]
 ldr r0,[r10,#32]
 ldr r12,=0x70000000
 ldr r0,[r12]
.global forbidden_fault_store
forbidden_fault_store: str r1,[r10]
after_fault:
 ldr r0,[r10]
 cmp r0,#0x100
 bne fail
 mov r9,#0
 mrs r0,cpsr
 bic r0,r0,#0x80
 msr cpsr_c,r0
.global irq_marker
irq_marker: nop
 .rept 32
 nop
 .endr
.global forbidden_irq_store
forbidden_irq_store: str r2,[r10,#4]
after_irq:
 cmp r9,#1
 bne fail
 ldr r0,[r10,#4]
 ldr r12,=0x101
 cmp r0,r12
 bne fail
 ldr r0,[r10]
 ldr r0,[r10,#32]
 mov r11,#7
sample_loop:
.global body_begin
body_begin: nop
.global stores_begin
stores_begin:
'''+ '\n'.join(f' str r{1+((i//16+i%4)%4)},[r10,#{(i%16)*4}]' for i in range(64))+'''
.global stores_end
stores_end:
 strb r1,[r10,#1]
 ldr r0,[r10]
 ldr r12,=0x44441144
 cmp r0,r12
 bne fail
 ldr r0,[r10,#60]
 cmp r0,r3
 bne fail
.global body_end
body_end: nop
 subs r11,r11,#1
 bne sample_loop
 mov r0,#0
 mcr p15,0,r0,c7,c14,0
 ldr r0,=0x50415353
 b finish
fail: ldr r0,=0x4641494c
finish: ldr r1,=0xf0000000
 str r0,[r1]
1: b 1b
abort_handler: ldr r12,=after_fault
 movs pc,r12
irq_handler: mov r9,#1
 ldr r12,=after_irq
 movs pc,r12
.ltorg
'''
(out/'program.S').write_text(program)
def call(cmd,name):
 with (out/name).open('w') as f:r=subprocess.run([str(x) for x in cmd],cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
 if r.returncode:raise RuntimeError(str(out/name))
call(['arm-none-eabi-gcc','-c','-mcpu=arm920t','-marm',out/'program.S','-o',out/'program.o'],'assemble.log')
call(['arm-none-eabi-ld','-T',ROOT/'sim/programs/link.ld',out/'program.o','-o',out/'program.elf'],'link.log')
call(['arm-none-eabi-objcopy','-O','binary',out/'program.elf',out/'program.bin'],'objcopy.log')
raw=(out/'program.bin').read_bytes();raw+=bytes((-len(raw))%4)
(out/'program.hex').write_text(''.join(f'{int.from_bytes(raw[i:i+4],"little"):08x}\n' for i in range(0,len(raw),4)))
(out/'empty.hex').write_text('00000000\n')
symbols={parts[2]:int(parts[0],16) for line in subprocess.check_output(['arm-none-eabi-nm',out/'program.elf']).decode().splitlines() if len(parts:=line.split())==3}
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
manifest=dict(source=base,runner_sha256=sha(Path(__file__)),image_id=subprocess.check_output(['docker','image','inspect','jotego/simulator:arm64','--format','{{.Id}}'],text=True).strip(),program_sha256=sha(out/'program.bin'),symbols=symbols,harness_sha256=sha(HERE/'tb.v'),observer_sha256=sha(HERE/'observe.vh'),control=a.control)
(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
docker=['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',str(ROOT)+':/work','-w','/work','--entrypoint']
cp=lambda p:'/work/'+str(p.relative_to(ROOT))
if a.reuse:
 old=json.loads((ROOT/a.reuse/'manifest.json').read_text());assert old['source']['source_id']==base['source_id'] and old['harness_sha256']==manifest['harness_sha256'] and old['observer_sha256']==manifest['observer_sha256']
 exe=ROOT/a.reuse/'obj/Vbench'
 assert old['executable_sha256']==sha(exe),'reused executable changed'
else:
 rtl=[source/'rtl/ngage_cpu.sv',source/'rtl/ngage_bram.v']
 for d in ['arm','arm920']:rtl+=sorted(p for p in (source/'rtl'/d).iterdir() if p.suffix in ['.v','.sv'])
 shutil.copyfile(HERE/'observe.vh',out/'observe.vh')
 (out/'tb.v').write_text((HERE/'tb.v').read_text().replace('tests/cpu/cpu_store_overlap/observe.vh',str((out/'observe.vh').relative_to(ROOT))))
 call(docker+['verilator','jotego/simulator:arm64','--binary','--timing','--assert','-j','4','-Wno-fatal','-Wno-lint','-DNGAGE_RUNTIME_TRACE','-DBENCH_HAS_LINE','-GLINE_ENABLE=1','--top-module','bench','--Mdir',cp(out/'obj'),'-I'+cp(source/'rtl/arm'),*[cp(f) for f in rtl],cp(out/'tb.v')],'build.log')
 exe=out/'obj/Vbench'
manifest['executable_sha256']=sha(exe)
(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
for repeat in range(2):
 call(docker+[cp(exe),'jotego/simulator:arm64','+program='+cp(out/'program.hex'),'+payload='+cp(out/'empty.hex'),'+firmware='+cp(out/'empty.hex'),f'+begin_pc={symbols["body_begin"]:x}',f'+end_pc={symbols["body_end"]:x}',f'+stores_begin={symbols["stores_begin"]:x}',f'+stores_end={symbols["stores_end"]:x}',f'+irq_marker={symbols["irq_marker"]:x}',f'+forbidden_fault={symbols["forbidden_fault_store"]:x}',f'+forbidden_irq={symbols["forbidden_irq_store"]:x}',*a.arg],f'run-{repeat}.log')
events=lambda p:[x for x in p.read_text().splitlines() if x.startswith(('OVERLAP','WINDOW','RESULT','PASS','PAIR'))]
assert events(out/'run-0.log')==events(out/'run-1.log'),'determinism mismatch'
assert any(x.startswith('PASS overlap') for x in events(out/'run-0.log'))
(out/'result.json').write_text(json.dumps(dict(status='PASS',source=base,events=events(out/'run-0.log')),indent=2)+'\n')
print('\n'.join(x for x in events(out/'run-0.log') if x.startswith(('WINDOW','OVERLAP_SUMMARY','PAIR','PASS'))))
