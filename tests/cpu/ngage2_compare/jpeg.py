#!/usr/bin/env python3
"""Separate original Thumb JPEG 8x8 block; not a six-kernel index member."""
import argparse,json,subprocess,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'tests/cpu/spmark_payload'))
import run as common
sys.path.insert(0,str(ROOT/'tests/cpu/cache_probe_retime'))
import workloads
import jpeg_workload
from jpeg_workload import make,oracle,ROM_SHA,BASE
from importlib.util import spec_from_file_location,module_from_spec
spec=spec_from_file_location('compare_driver',HERE/'run.py');driver=module_from_spec(spec);spec.loader.exec_module(driver)
p=argparse.ArgumentParser();p.add_argument('--cpu',choices=['5c','base','ngage2','arm9v2'],required=True);p.add_argument('--name',required=True);p.add_argument('--scalar-refills',action='store_true');p.add_argument('--jpeg',type=Path,default=jpeg_workload.JPEG);p.add_argument('--arm9v2-netlist',type=Path);a=p.parse_args()
if a.arm9v2_netlist and a.cpu!='arm9v2':p.error('--arm9v2-netlist requires --cpu arm9v2')
jpeg_workload.JPEG=a.jpeg
donor=a.cpu in ('ngage2','arm9v2')
import re
assert re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,63}',a.name)
out=ROOT/'build/sim/jpeg-payload'/a.name;out.mkdir(parents=True,exist_ok=False)
result=dict(status='INCOMPLETE',rows=[]);common.save(out/'result.json',result)
try:
 c=make();rom=(ROOT/'build/firmware/nem4-factory/core.bin').read_bytes();assert common.sha(rom)==ROM_SHA
 expected=oracle(c,rom)
 # Unicorn reports a Thumb BL pair as one 32-bit instruction. ARM9V2
 # architecturally completes the two halfwords; require exact suffix PCs
 # and counts as well as the normalized original instruction histogram.
 import struct
 suffixes={}
 for k,count in expected['pcs'].items():
  pc=int(k,16);off=pc-0x50000000
  h0,h1=struct.unpack_from('<HH',rom,off)
  if h0&0xf800==0xf000 and h1&0xf800==0xf800:suffixes[pc+2]=count
 expected['thumb_bl_suffixes']={hex(k):v for k,v in suffixes.items()}
 common.save(out/'oracle.json',expected)
 common.hexfile(out/'payload.hex',rom[0x500000:0x600000]);common.hexfile(out/'firmware.hex',rom[0x300000:0x400000])
 bench=common.support();source=out/'source'
 if a.cpu in ('5c','base'):
  frozen=bench.snapshot(source,revision=driver.REV if a.cpu=='5c' else 'a2c5863')
  rtl=[source/'rtl/ngage_cpu.sv',source/'rtl/ngage_bram.v']
  for directory in ['rtl/arm','rtl/arm920']:rtl+=sorted(x for x in (source/directory).iterdir() if x.suffix in ['.sv','.v'])
  inputs=[common.cpath(x) for x in rtl]
 elif a.cpu=='arm9v2':
  frozen=driver.integrated_snapshot(source,a.arm9v2_netlist)
  inputs=['-DNGAGE_ARM9V2']+[common.cpath(source/x) for x in driver.ARM9V2_FILES]
 else:
  names=['rtl/cpu/arm925t_gen.v','sim/stubs/altsyncram.sv','sim/stubs/altdpram.sv']
  frozen=dict(commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=driver.DONOR,text=True).strip(),files={x:common.sha((driver.DONOR/x).read_bytes()) for x in names})
  inputs=['/donor/'+x for x in names]
 programs={};workloads.PAYLOAD_BASE=BASE
 for bad in [False,True]:
  n='jpeg'+('-wrong-output' if bad else '')
  asm=workloads.assembly(c,corrupt=bad).replace('ldr r0,=0x10000c0e','ldr r0,=0x50500c0e').replace('str r0,[r4,#0x400]','ldr r5,=0x1414\n str r0,[r4,r5]')
  (out/(n+'.S')).write_text(asm)
  for cmd,log in [(['arm-none-eabi-gcc','-c','-mcpu=arm920t',out/(n+'.S'),'-o',out/(n+'.o')],'assemble'),(['arm-none-eabi-ld','-T',ROOT/'sim/programs/link.ld',out/(n+'.o'),'-o',out/(n+'.elf')],'link'),(['arm-none-eabi-objcopy','-O','binary',out/(n+'.elf'),out/(n+'.bin')],'objcopy')]:common.command(cmd,out/(n+'.'+log+'.log'))
  common.hexfile(out/(n+'.hex'),(out/(n+'.bin')).read_bytes());programs[n]=dict(bench.symbols(subprocess.check_output(['arm-none-eabi-nm',out/(n+'.elf')],text=True)),sha256=common.sha((out/(n+'.bin')).read_bytes()))
 tb=(ROOT/'tests/cpu/spmark_payload/tb.v').read_text()
 tb=driver.observe_cpu(tb,a.cpu,a.scalar_refills).replace("32'h10000000","32'h50500000").replace("32'h10100000","32'h50600000")
 if a.arm9v2_netlist:tb=driver.observe_cache_metrics(tb)
 (out/'tb.v').write_text(tb)
 docker=['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',str(ROOT)+':/work']
 if a.cpu=='ngage2':docker+=['-v',str(driver.DONOR)+':/donor:ro']
 docker+=['-w','/work','--entrypoint']
 common.command(docker+['verilator',common.IMAGE,'--binary','--timing','--assert','-j','2','-Wno-fatal','-Wno-lint','-DNGAGE_RUNTIME_TRACE','-DBENCH_HAS_LINE','-GLINE_ENABLE=1','--top-module','bench','--Mdir',common.cpath(out/'obj'),'-I'+common.cpath(source/'rtl/arm')]+inputs+[common.cpath(out/'tb.v')],out/'build.log')
 exe=out/'obj/Vbench'
 result['manifest']=dict(cpu=a.cpu,source=frozen,programs=programs,executable_sha256=common.sha(exe.read_bytes()),harness_sha256=common.sha(tb.encode()),rom_sha256=ROM_SHA,jpeg_sha256=common.sha(a.jpeg.read_bytes()),oracle=expected,image_id=subprocess.check_output(['docker','image','inspect',common.IMAGE,'--format','{{.Id}}'],text=True).strip())
 for bad in [False,True]:
  n='jpeg'+('-wrong-output' if bad else '')
  for profile in ['0:0'] if bad else ['0:0','2:9']:
   observations=[];iw,dw=profile.split(':')
   for r in range(1 if bad else 2):
    log=out/f'{n}-{iw}-{dw}-{r}.log';sy=programs[n]
    cmd=docker+[common.cpath(exe),common.IMAGE,'+program='+common.cpath(out/(n+'.hex')),'+payload='+common.cpath(out/'payload.hex'),'+firmware='+common.cpath(out/'firmware.hex'),f'+begin_pc={sy["body_begin"]:x}',f'+end_pc={sy["body_end"]:x}',f'+i_wait={iw}',f'+d_wait={dw}','+max_cycles=12000000','+ngage-compact-trace','+compare_trace=1']
    try:common.command(cmd,log)
    except RuntimeError:
     if bad and 'guest result check failed' in log.read_text():result['wrong_output_rejected']=True;continue
     raise
    if bad:raise AssertionError('wrong output accepted')
    text=log.read_text();obs=bench.parse_log(text,c)
    windows=[dict((k,int(v)) for k,v in re.findall(r'(\w+)=(\d+)',l)) for l in text.splitlines() if l.startswith('PAYLOAD_WINDOW ')]
    pcs=expected['pcs'];np=sum(v for k,v in pcs.items() if BASE<=int(k,16)<BASE+0x100000);nh=sum(v for k,v in pcs.items() if 0x50300000<=int(k,16)<0x50400000)
    assert len(windows)==7 and all(w['payload_retire_proxy']==np+(sum(suffixes.values()) if donor else 0) and w['helper_retire_proxy']==nh for w in windows),'payload/helper oracle differs'
    if donor:
     from collections import Counter
     got=Counter(int(l.split('pc=')[1],16) for l in text.splitlines() if l.startswith('TRACE_RET') and BASE<=int(l.split('pc=')[1],16)<BASE+0x100000)
     predicted=Counter({int(k,16):v for k,v in pcs.items() if BASE<=int(k,16)<BASE+0x100000})+Counter(suffixes)
     assert got==predicted,'Thumb PC histogram differs after explicit BL-half accounting'
    observations.append(obs)
   if not bad:
    assert observations[0]==observations[1]
    result['rows'].append(dict(case=c['id'],profile=profile,**observations[0]));common.save(out/'result.json',result);print(a.cpu,'JPEG',profile,obs['body_cycles_median'],flush=True)
 for name,h in frozen['files'].items():assert common.sha(((driver.DONOR if a.cpu=='ngage2' else source)/name).read_bytes())==h
 result['status']='PASS';common.save(out/'result.json',result)
except Exception as exc:
 result.update(status='FAIL',error=str(exc));common.save(out/'result.json',result);raise
