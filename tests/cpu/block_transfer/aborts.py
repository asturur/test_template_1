#!/usr/bin/env python3
"""Check precise LDM/STM aborts at all eight beats, in an isolated CPU fixture."""
import argparse
import json
import os
import re
import shlex
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--name',required=True)
p.add_argument('--reference-dir',help='Optional repository-relative frozen RTL overrides')
a=p.parse_args()
if not re.fullmatch(r'[A-Za-z0-9_-]+',a.name):p.error('invalid run name')
out=ROOT/'build/sim'/a.name
out.mkdir(parents=True,exist_ok=False)
rel=str(out.relative_to(ROOT));script=out/'run-cpu.sh';fixture=out/'test.sv'
s=(ROOT/'tests/cpu/core/sim.sh').read_text()
s=re.sub(r'^root=.*$', 'root='+shlex.quote(str(ROOT)),s,flags=re.M)
s=s.replace('build/sim/unit-core',rel).replace('tests/cpu/core/test.sv',str(fixture.relative_to(ROOT)))
s=s.replace('extra_define="-DNGAGE_OPERAND_REFERENCE"','extra_define=""')
s=s.replace('--rm --network none','--rm --pull=never --network none').replace('--binary --timing','--binary -j 3 --timing')
script.write_text(s)
fixture.write_text((ROOT/'tests/cpu/core/test.sv').read_text().replace('build/sim/unit-core',rel))
result={'status':'INCOMPLETE','runs':{}}
try:
 for store in [False,True]:
  for mode in range(4):
   for word in range(8):
    name=f'{"stm" if store else "ldm"}-{mode}-{word}'
    env={k:v for k,v in os.environ.items() if not k.startswith('CPU_')}
    env.update(CPU_PROGRAM='block_transfer_abort',CPU_MAX_CYCLES='100000',CPU_DELAYS='0 3',CPU_LOAD_FORWARD_CHECK='1',CPU_BRANCH_OWNER_CHECK='1',CPU_ASM_DEFINES=f'-DBLOCK_MODE={mode} -DFAULT_WORD={word}'+(' -DBLOCK_STORE' if store else ''),CPU_FAULT_ADDR=f'{0x80001000+word*4:x}',CPU_RUN_ARGS='+fault_write_only' if store else '+fault_read_only')
    if a.reference_dir:env['CPU_REFERENCE_DIR']=a.reference_dir
    with (out/(name+'.log')).open('w') as log:subprocess.run(['sh',str(script)],cwd=ROOT,check=True,env=env,stdout=log,stderr=subprocess.STDOUT)
    for delay in [0,3]:
     f=out/f'run-{delay}.log';text=f.read_text();assert 'PASS: CPU test' in text
     result['runs'][f'{name}-{delay}']=[x for x in text.splitlines() if x.startswith(('PASS:','COUNTERS:'))];f.rename(out/f'{name}-{delay}.log')
    print('PASS',name,flush=True)
    (out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
 result['status']='PASS'
except Exception:
 result['status']='FAIL';raise
finally:(out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
