#!/usr/bin/env python3
"""Independent 64-LDR-pair microbenchmark; reuses a hash-checked matched CPU build."""
from setup import *
import argparse,subprocess,sys,re,struct
p=argparse.ArgumentParser();p.add_argument('name');p.add_argument('--build',type=Path,required=True);a=p.parse_args()
out=ROOT/'build/sim/cpu-load-overlap'/a.name;out.mkdir(parents=True,exist_ok=False)
(out/'result.json').write_text('{"status":"INCOMPLETE"}\n')
build=(ROOT/a.build).resolve();manifest=json.loads((build/'manifest.json').read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
exe=ROOT/manifest['executable'];assert sha(exe)==manifest['executable_sha256']
for f,v in manifest['source']['files'].items():assert sha(build/'source'/f)==v
sys.path.insert(0,str(ROOT/'tests/cpu/spmark_payload'))
from workloads import assembly,words
from oracle import verify
c=dict(id='independent_load_pairs',module='synthetic',entry=0,iterations=1,operations=64,unit='independent LDR pairs',writes=[(0x80001000,words([0x100+i for i in range(8)]))],regs=[0x80001000,0],strides=[0,0],checks=[(0x80001018,words([64*(0x101+0x104)]))],warmups=3,samples=5)
def call(cmd,log):
 with (out/log).open('w') as f:r=subprocess.run([str(x) for x in cmd],cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
 if r.returncode:raise RuntimeError(str(out/log))
def assemble(name,s):
 (out/(name+'.S')).write_text(s)
 call(['arm-none-eabi-gcc','-c','-mcpu=arm920t','-marm',out/(name+'.S'),'-o',out/(name+'.o')],name+'.assemble.log')
 call(['arm-none-eabi-ld','-T',ROOT/'sim/programs/link.ld',out/(name+'.o'),'-o',out/(name+'.elf')],name+'.link.log')
 call(['arm-none-eabi-objcopy','-O','binary',out/(name+'.elf'),out/(name+'.bin')],name+'.objcopy.log')
 raw=(out/(name+'.bin')).read_bytes();raw+=bytes((-len(raw))%4)
 (out/(name+'.hex')).write_text(''.join(f'{int.from_bytes(raw[i:i+4],"little"):08x}\n' for i in range(0,len(raw),4)))
 return raw
# No stores or address updates between pairs. Dependent additions consume BOTH
# values each time, and a final store publishes the independently computed sum.
payload=assemble('payload','.syntax unified\n.cpu arm920t\n.arm\n.global _start\n_start:\n'+''.join('ldr r2,[r0,#4]\nldr r3,[r0,#16]\nadd r1,r1,r2\nadd r1,r1,r3\n' for _ in range(64))+'str r1,[r0,#24]\nbx lr\n')
oracle=verify(c,payload,b'\0'*4)
(out/'empty.hex').write_text('00000000\n')
docker=['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',str(ROOT)+':/work','-w','/work','--entrypoint']
cp=lambda p:'/work/'+str(p.relative_to(ROOT))
results=[];qualification=[]
for bad in [False,True]:
 name='wrong-output' if bad else 'program'
 raw=assemble(name,assembly(c,corrupt=bad).replace('body_end:\n nop','body_end:\n nop\n .rept 16\n nop\n .endr'))
 symbols={x[2]:int(x[0],16) for l in subprocess.check_output(['arm-none-eabi-nm',out/(name+'.elf')],text=True).splitlines() if len(x:=l.split())==3}
 for iw,dw in [(0,0)] if bad else [(0,0),(2,9)]:
  observations=[]
  for repeat in range(1 if bad else 2):
   log=f'{name}-{iw}-{dw}-{repeat}.log'
   try:call(docker+[cp(exe),'jotego/simulator:arm64','+program='+cp(out/(name+'.hex')),'+payload='+cp(out/'payload.hex'),'+firmware='+cp(out/'empty.hex'),f'+begin_pc={symbols["body_begin"]:x}',f'+end_pc={symbols["body_end"]:x}',f'+i_wait={iw}',f'+d_wait={dw}'],log)
   except RuntimeError:
    if bad and 'guest result check failed' in (out/log).read_text():qualification.append('wrong checksum rejected');continue
    raise
   if bad:raise RuntimeError('wrong checksum accepted')
   lines=(out/log).read_text().splitlines()
   windows=[dict((k,int(v)) for k,v in re.findall(r'(\w+)=(\d+)',l)) for l in lines if l.startswith('WINDOW ')]
   ops=[dict((k,int(v)) for k,v in re.findall(r'(\w+)=(\d+)',l)) for l in lines if l.startswith('PAYLOAD_WINDOW ')]
   assert len(windows)==8 and len(ops)==8
   assert all(x['payload_retire_proxy']==oracle['payload_instructions'] and x['helper_retire_proxy']==0 for x in ops)
   assert len({x['cycles'] for x in windows[3:]})==1
   assert all(x['reads']==x['writes']==x['lines']==0 for x in windows[3:])
   observations.append(windows)
  if not bad:
   assert observations[0]==observations[1]
   results.append(dict(profile=f'{iw}:{dw}',windows=observations[0],cycles=observations[0][3]['cycles']))
result=dict(status='PASS',warmups=3,samples=5,deterministic_repeats=2,build=str(build.relative_to(ROOT)),source_id=manifest['source']['source_id'],executable_sha256=sha(exe),program_sha256=sha(out/'program.bin'),payload_sha256=sha(out/'payload.bin'),oracle=oracle,rows=results,qualification=qualification)
(out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
print('PASS independent 64-LDR-pair loop:',[(r['profile'],r['cycles']) for r in results])
