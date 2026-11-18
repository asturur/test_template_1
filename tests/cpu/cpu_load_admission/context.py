#!/usr/bin/env python3
import argparse,json,subprocess,hashlib,shutil
from pathlib import Path
from setup import ROOT,HERE
p=argparse.ArgumentParser();p.add_argument('--build',type=Path,required=True);p.add_argument('--name',required=True);a=p.parse_args()
build=ROOT/a.build;out=ROOT/'build/sim/cpu-load-admission'/a.name;out.mkdir(exist_ok=False)
manifest=json.loads((build/'manifest.json').read_text());src=build/'source'
files=[src/'rtl/ngage_bram.v',src/'rtl/arm/zap_dcache.sv',*sorted((src/'rtl/arm920').glob('*.sv')),HERE/'context_test.sv']
cp=lambda p:'/work/'+str(p.relative_to(ROOT));docker=['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',str(ROOT)+':/work','-w','/work','--entrypoint']
def call(cmd,log):
    with (out/log).open('w') as f:r=subprocess.run(cmd,cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
    assert r.returncode==0,str(out/log)
call(docker+['verilator','jotego/simulator:arm64','--binary','--timing','--assert','-j','1','-Wno-fatal','-Wno-lint','--top-module','test','--Mdir',cp(out/'obj'),'-I'+cp(src/'rtl/arm')]+[cp(f) for f in files],'build.log')
rows=[]
for n in range(2):
    call(docker+[cp(out/'obj/Vtest'),'jotego/simulator:arm64'],f'run-{n}.log')
    rows.append([l for l in (out/f'run-{n}.log').read_text().splitlines() if l.startswith(('ADMISSION_CONTEXT','PASS admission'))])
assert rows[0]==rows[1] and any(l.startswith('PASS admission') for l in rows[0])
(out/'result.json').write_text(json.dumps(dict(status='PASS',source=manifest['source'],events=rows[0],inputs={str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in files},executable_sha256=hashlib.sha256((out/'obj/Vtest').read_bytes()).hexdigest()),indent=2)+'\n')
print('\n'.join(rows[0]))
