#!/usr/bin/env python3
"""Real donor observer controls: held boundary, redirected and faulted markers.

Run after a normal donor run; reuses its hash-qualified executable and payload.
No production or donor RTL is modified.
"""
import argparse,hashlib,json,re,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'tests/cpu/spmark_payload'))
import run as common
from workloads import cases,assembly
p=argparse.ArgumentParser();p.add_argument('--base',type=Path,required=True);p.add_argument('--name',required=True);a=p.parse_args()
out=ROOT/'build/sim/ngage2-observer'/a.name;out.mkdir(parents=True,exist_ok=False)
base=a.base.resolve();m=json.loads((base/'manifest.json').read_text())
exe=ROOT/m['executable'];assert common.sha(exe.read_bytes())==m['executable_sha256']
b=common.support()
# Same original function and checked outputs, but only one window. The marked
# uncached LDR must complete before a begin event; this is a qualification
# guest, never one of the six comparison measurements.
c=cases()[0];c['warmups']=0;c['samples']=1
asm=assembly(c)
# Add an uncached alias of the physical test RAM. AP/domain remain identical.
asm=asm.replace(' mcr p15,0,r4,c2,c0,0',' ldr r0,=0x0a000c02\n ldr r5,=0x2400\n str r0,[r4,r5]\n mcr p15,0,r4,c2,c0,0')
asm=asm.replace('body_begin:\n nop','body_begin:\n ldr r10,=0x90000000\n.global held_marker\nheld_marker:\n ldr r10,[r10]\n.global after_held\nafter_held:\n nop')
# A taken data-dependent PC write redirects through W and flushes sequential
# records. The skipped marker cannot be observed as an executed boundary.
asm=asm.replace('body_end:\n nop','''body_end:
 nop
 ldr r10,=redirect_done
 mov pc,r10
.global ghost_begin
ghost_begin:
 nop
.global ghost_end
ghost_end:
 nop
redirect_done:
 ldr r10,=0xa0000000
.global fault_begin
fault_begin:
 ldr r10,[r10]
.global fault_end
fault_end:
 nop
fault_return:
''')
# Data-abort vector returns after both the faulting marker and fault_end.
asm=asm.replace(' .rept 7\n b fail\n .endr',' b fail\n b fail\n b fail\n b data_abort\n b fail\n b fail\n b fail')
asm += '\n.balign 4\ndata_abort:\n ldr lr,=fault_return\n movs pc,lr\n'
(out/'qualify.S').write_text(asm)
for cmd,log in [(['arm-none-eabi-gcc','-c','-mcpu=arm920t',out/'qualify.S','-o',out/'qualify.o'],'assemble.log'),(['arm-none-eabi-ld','-T',ROOT/'sim/programs/link.ld',out/'qualify.o','-o',out/'qualify.elf'],'link.log'),(['arm-none-eabi-objcopy','-O','binary',out/'qualify.elf',out/'qualify.bin'],'objcopy.log')]:common.command(cmd,out/log)
common.hexfile(out/'qualify.hex',(out/'qualify.bin').read_bytes())
nm=subprocess.check_output(['arm-none-eabi-nm',out/'qualify.elf'],text=True)
sy={x[2]:int(x[0],16) for l in nm.splitlines() if len(x:=l.split())==3}
docker=['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',str(ROOT)+':/work','-w','/work','--entrypoint',common.cpath(exe),common.IMAGE]
results=[]
for kind,beg,end,expected in [('held','held_marker','body_end',1),('flushed','ghost_begin','ghost_end',0),('fault','fault_begin','fault_end',0)]:
 log=out/(kind+'.log')
 common.command(docker+['+program='+common.cpath(out/'qualify.hex'),'+payload='+common.cpath(base/'3DTEST.DLL.hex'),'+firmware='+common.cpath(base/'firmware.hex'),f'+begin_pc={sy[beg]:x}',f'+end_pc={sy[end]:x}','+i_wait=2','+d_wait=37','+max_cycles=3000000','+compare_trace=2'],log)
 text=log.read_text();windows=[l for l in text.splitlines() if l.startswith('WINDOW ')]
 assert len(windows)==expected,(kind,windows)
 assert f'RESULT windows={expected} ' in text
 if kind=='held':
  events=[dict(re.findall(r'(\w+)=([\da-f]+)',l)) for l in text.splitlines() if l.startswith('QUAL ') and 'pc='+f'{sy[beg]:08x}' in l]
  assert len(events)==1,events
  assert int(events[0]['held'])>=30,events
 if kind=='fault':assert re.search(r'EXCEPTION .*dabt=1',text),'fault was not actually taken'
 results.append(dict(kind=kind,status='PASS',windows=expected))
common.save(out/'result.json',dict(status='PASS',controls=results,base=str(base),executable_sha256=m['executable_sha256'],program_sha256=common.sha((out/'qualify.bin').read_bytes()),symbols=sy))
print('PASS',out/'result.json')
