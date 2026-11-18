from pathlib import Path
import sys,json,subprocess,copy,argparse
ROOT=Path(__file__).resolve().parents[3];sys.path.insert(0,str(ROOT/'tests/cpu/spmark_payload'))
import run as common,workloads
from workload import cases,BASE
parser=argparse.ArgumentParser();parser.add_argument('--base',type=Path,default=ROOT/'build/sim/jpeg-payload/error-diffusion-20261115-v2');args=parser.parse_args();O=args.base.resolve();O.relative_to(ROOT);workloads.PAYLOAD_BASE=BASE;bench=common.support();records=[]
docker=['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',str(ROOT)+':/work','-w','/work','--entrypoint']
for c in cases():
 test=copy.deepcopy(c);addr,raw=c['checks'][-1];assert addr==0x80003000
 test['checks'].insert(0,(addr+16,raw[16:-16]))
 name=c['id']+'-wrong-pixel';asm=workloads.assembly(test,corrupt=True).replace('ldr r0,=0x10000c0e','ldr r0,=0x50500c0e').replace('str r0,[r4,#0x400]','ldr r5,=0x1414\n str r0,[r4,r5]');(O/(name+'.S')).write_text(asm)
 for cmd,kind in [(['arm-none-eabi-gcc','-c','-mcpu=arm920t',O/(name+'.S'),'-o',O/(name+'.o')],'assemble'),(['arm-none-eabi-ld','-T',ROOT/'sim/programs/link.ld',O/(name+'.o'),'-o',O/(name+'.elf')],'link'),(['arm-none-eabi-objcopy','-O','binary',O/(name+'.elf'),O/(name+'.bin')],'objcopy')]:common.command(cmd,O/(name+'.'+kind+'.log'))
 raw=(O/(name+'.bin')).read_bytes();common.hexfile(O/(name+'.hex'),raw);sy=bench.symbols(subprocess.check_output(['arm-none-eabi-nm',O/(name+'.elf')],text=True));log=O/(name+'.log')
 try:common.command(docker+[common.cpath(O/'obj/Vbench'),common.IMAGE,'+program='+common.cpath(O/(name+'.hex')),'+payload='+common.cpath(O/'ROM505.hex'),'+firmware='+common.cpath(O/'firmware.hex'),f'+begin_pc={sy["body_begin"]:x}',f'+end_pc={sy["body_end"]:x}','+max_cycles=12000000','+ngage-compact-trace'],log)
 except RuntimeError:assert 'guest result check failed' in log.read_text()
 else:raise AssertionError('bad pixel accepted')
 records.append(dict(case=c['id'],status='REJECTED',corrupted_expected_address=hex(addr+16),program_sha256=common.sha(raw)));print('PASS rejected wrong output pixel',c['id'],flush=True)
common.save(O/'pixel-controls.json',dict(status='PASS',controls=records))
