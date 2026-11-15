from pathlib import Path
import sys,json,subprocess,shutil,hashlib,re,statistics,os,argparse
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tests/cpu/spmark_payload'))
import run as common
# Explicit import avoids the Python stdlib profile module.
import importlib.util
spec=importlib.util.spec_from_file_location('payload_profile',ROOT/'tests/cpu/spmark_payload/profile.py');prof=importlib.util.module_from_spec(spec);spec.loader.exec_module(prof)
import workloads
from workload import cases,oracle,ROM_SHA,BASE
P=Path(__file__).resolve().parent
parser=argparse.ArgumentParser();parser.add_argument('--name',default='error-diffusion-20261115-v2');args=parser.parse_args()
assert re.fullmatch(r'[A-Za-z0-9_-]+',args.name),'invalid output name'
O=ROOT/'build/sim/jpeg-payload'/args.name;O.mkdir(parents=True,exist_ok=False)
result=dict(status='INCOMPLETE',meaning='Original native Thumb error-diffusion hotspot, not whole JPEG/OS or SPMark score',rows=[])
def save():common.save(O/'result.json',result)
save()
try:
 rom=(ROOT/'build/firmware/nem4-factory/core.bin').read_bytes();assert common.sha(rom)==ROM_SHA
 selected=cases();oracles={c['id']:oracle(c,rom) for c in selected};common.save(O/'oracle.json',oracles)
 bench=common.support();source=O/'source';frozen=bench.snapshot(source)
 workloads.PAYLOAD_BASE=BASE
 common.hexfile(O/'ROM505.hex',rom[0x500000:0x600000]);common.hexfile(O/'firmware.hex',rom[0x300000:0x400000])
 programs={}
 for c in selected:
  for bad in (False,True):
   name=c['id']+('-wrong-output' if bad else '');asm=workloads.assembly(c,corrupt=bad)
   assert 'ldr r0,=0x10000c0e' in asm and 'str r0,[r4,#0x400]' in asm
   asm=asm.replace('ldr r0,=0x10000c0e','ldr r0,=0x50500c0e').replace('str r0,[r4,#0x400]','ldr r5,=0x1414\n str r0,[r4,r5]')
   (O/(name+'.S')).write_text(asm)
   linker=ROOT/'sim/programs/link.ld'
   common.command(['arm-none-eabi-gcc','-c','-mcpu=arm920t',O/(name+'.S'),'-o',O/(name+'.o')],O/(name+'.assemble.log'))
   common.command(['arm-none-eabi-ld','-T',linker,O/(name+'.o'),'-o',O/(name+'.elf')],O/(name+'.link.log'))
   common.command(['arm-none-eabi-objcopy','-O','binary',O/(name+'.elf'),O/(name+'.bin')],O/(name+'.objcopy.log'))
   raw=(O/(name+'.bin')).read_bytes();common.hexfile(O/(name+'.hex'),raw);syms=bench.symbols(subprocess.check_output(['arm-none-eabi-nm',O/(name+'.elf')],text=True));programs[name]=dict(syms,sha256=common.sha(raw))
 tb=(ROOT/'tests/cpu/spmark_payload/tb.v').read_text().replace("32'h10000000","32'h50500000").replace("32'h10100000","32'h50600000")
 observer=ROOT/'tests/cpu/spmark_payload/profile.vh';observer_text=observer.read_text().replace("32'h10000000","32'h50500000").replace("32'h10100000","32'h50600000");(O/'profile.vh').write_text(observer_text)
 changes=[('    initial begin\n','    `include "profile.vh"\n\n    initial begin\n'),('            if(retire && retire_pc==begin_pc)','            if(start_cycle>=0)prof_sample();\n            if(retire && retire_pc==begin_pc)'),('start_helper_ops=helper_ops;','start_helper_ops=helper_ops;prof_begin();'),('                windows=windows+1;','                prof_end();\n                windows=windows+1;'),('                        $display("RESULT ','                        prof_dump();\n                        $display("RESULT ')]
 (O/'tb-base.v').write_text(tb)
 for old,new in changes:assert tb.count(old)==1,old;tb=tb.replace(old,new)
 (O/'tb.v').write_text(tb)
 image_id=subprocess.check_output(['docker','image','inspect',common.IMAGE,'--format','{{.Id}}'],text=True).strip()
 manifest=dict(format='jpeg-native-block-v1',source=frozen,image_id=image_id,programs=programs,rom_sha256=ROM_SHA,payload_sha256=common.sha(rom[0x500000:0x600000]),harness_sha256=common.sha(tb.encode()),observer_sha256=common.sha(observer_text.encode()))
 common.save(O/'manifest.json',manifest);result['manifest']=manifest;save()
 docker=['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',str(ROOT)+':/work','-w','/work','--entrypoint']
 rtl=[source/'rtl/ngage_cpu.sv',source/'rtl/ngage_bram.v']
 for directory in ['rtl/arm','rtl/arm920']:rtl+=sorted(p for p in (source/directory).iterdir() if p.suffix in ('.v','.sv'))
 common.command(docker+['verilator',common.IMAGE,'--binary','--timing','--assert','-j','3','-Wno-fatal','-Wno-lint','-DNGAGE_RUNTIME_TRACE','-DBENCH_HAS_LINE','-GLINE_ENABLE=1','--top-module','bench','--Mdir',common.cpath(O/'obj'),'-I'+common.cpath(source/'rtl/arm'),'-I'+common.cpath(O)]+[common.cpath(p) for p in rtl]+[common.cpath(O/'tb.v')],O/'build.log')
 print('Compiled current frozen CPU/cache',flush=True)
 for c in selected:
  for memory in ('0:0','2:9'):
   iw,dw=memory.split(':');observations=[];profiles=[]
   for repeat in range(2):
    sy=programs[c['id']];log=O/f'{c["id"]}-{iw}-{dw}-{repeat}.log'
    cmd=docker+[common.cpath(O/'obj/Vbench'),common.IMAGE,'+program='+common.cpath(O/(c['id']+'.hex')),'+payload='+common.cpath(O/'ROM505.hex'),'+firmware='+common.cpath(O/'firmware.hex'),f'+begin_pc={sy["body_begin"]:x}',f'+end_pc={sy["body_end"]:x}',f'+i_wait={iw}',f'+d_wait={dw}','+max_cycles=12000000','+ngage-compact-trace']
    common.command(cmd,log);text=log.read_text();obs=bench.parse_log(text,c);pr=prof.parse_profile(text,obs);observations.append(obs);profiles.append(pr)
   assert observations[0]==observations[1] and profiles[0]==profiles[1],'repeat differs'
   row=dict(case=c['id'],memory_profile=memory,observation=observations[0],profile=profiles[0],oracle=oracles[c['id']]);result['rows'].append(row);save();print('PASS',c['id'],memory,observations[0]['body_cycles_median'],flush=True)
  name=c['id']+'-wrong-output';sy=programs[name];log=O/(name+'.log')
  cmd=docker+[common.cpath(O/'obj/Vbench'),common.IMAGE,'+program='+common.cpath(O/(name+'.hex')),'+payload='+common.cpath(O/'ROM505.hex'),'+firmware='+common.cpath(O/'firmware.hex'),f'+begin_pc={sy["body_begin"]:x}',f'+end_pc={sy["body_end"]:x}','+max_cycles=12000000','+ngage-compact-trace']
  try:common.command(cmd,log)
  except RuntimeError:
   assert 'guest result check failed' in log.read_text(),'wrong-output failed for wrong reason'
  else:raise AssertionError('wrong output accepted')
 for name,h in frozen['files'].items():assert common.sha((source/name).read_bytes())==h,'frozen source changed'
 result['status']='PASS';save()
except Exception as exc:
 result.update(status='FAIL',error=str(exc));save();raise
