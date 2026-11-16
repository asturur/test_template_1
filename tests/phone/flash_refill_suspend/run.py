#!/usr/bin/env python3
"""Real CPU deferred-erase/refill regression in the existing simulator image."""
import argparse
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT/'build/sim/unit-flash-refill-suspend'

def call(args, **kw):
    return subprocess.run(args, cwd=ROOT, check=True, **kw)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--negative-control', action='store_true')
    args=parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    program=ROOT/'sim/programs/flash_refill_suspend.S'
    call(['arm-none-eabi-gcc','-c','-mcpu=arm920t','-marm',str(program),'-o',str(OUT/'program.o')])
    call(['arm-none-eabi-ld','-T','sim/programs/link.ld',str(OUT/'program.o'),'-o',str(OUT/'program.elf')])
    call(['arm-none-eabi-objcopy','-O','binary',str(OUT/'program.elf'),str(OUT/'program.bin')])
    binary=(OUT/'program.bin').read_bytes();binary+=bytes(-len(binary)%4)
    (OUT/'program.hex').write_text(''.join(f'{int.from_bytes(binary[i:i+4],"little"):08x}\n' for i in range(0,len(binary),4)))
    mode='negative' if args.negative_control else 'production'
    sources=re.findall(r'-name (?:SYSTEMVERILOG_FILE|VERILOG_FILE) (rtl/\S+)',(ROOT/'files.qip').read_text())
    if args.negative_control:
        text=(ROOT/'rtl/ngage_mister.v').read_text()
        old='code_idle && user_ready && !memory_req && !flash_issued;'
        assert text.count(old)==1
        (OUT/'old-refill-gate.v').write_text(text.replace(old,'code_idle && user_idle && !memory_req && !flash_issued;'))
        sources=[str((OUT/'old-refill-gate.v').relative_to(ROOT)) if p=='rtl/ngage_mister.v' else p for p in sources]
    # Arguments are passed as an array, with no generated shell command.
    compile_args=['verilator','--binary','--timing','--assert','-j','4','-Wno-fatal','-Wno-lint',
                  '-Irtl/arm','--top-module','tb','--Mdir',str((OUT/('obj-'+mode)).relative_to(ROOT)),
                  *sources,'tests/phone/flash_refill_suspend/tb.v']
    runner="""import json,pathlib,subprocess,sys
args=json.loads(sys.argv[1]);out=pathlib.Path(sys.argv[2]);mode=sys.argv[3]
with (out/('build-'+mode+'.log')).open('w') as log:
 subprocess.run(args,stdout=log,stderr=subprocess.STDOUT,check=True)
with (out/('run-'+mode+'.log')).open('w') as log:
 result=subprocess.run([str(out/('obj-'+mode)/'Vtb')],stdout=log,stderr=subprocess.STDOUT)
text=(out/('run-'+mode+'.log')).read_text()
if mode=='negative':
 assert result.returncode!=0 and 'DEFERRED_ERASE_REFILL_DEADLOCK' in text, text[-2000:]
 print('PASS negative control: original gate reproduces deferred erase/refill deadlock')
else:
 assert result.returncode==0 and 'PASS real CPU erase-suspend' in text, text[-2000:]
 print(next(line for line in text.splitlines() if line.startswith('PASS real CPU')))
"""
    import json
    call(['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64',
          '-v',str(ROOT)+':/work','-w','/work','--entrypoint','python3','jotego/simulator:arm64',
          '-c',runner,json.dumps(compile_args),str(OUT.relative_to(ROOT)),mode])

if __name__=='__main__':main()
