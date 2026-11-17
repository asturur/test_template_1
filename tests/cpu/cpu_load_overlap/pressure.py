#!/usr/bin/env python3
"""Actual adapter/cache full-pressure test; delay only response publication."""
from pathlib import Path
import argparse,json,hashlib,subprocess,shutil
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('name');a=p.parse_args()
out=ROOT/'build/sim/cpu-load-overlap'/a.name;out.mkdir(parents=True,exist_ok=False)
src=out/'source';src.mkdir()
for f in (ROOT/'rtl/arm920').glob('*.sv'):
 original=ROOT/'tests/cpu/cache_probe_retime/rtl'/f.name
 old=ROOT/'tests/cpu/cpu_load_delivery/rtl/arm920'/f.name
 new=HERE/'rtl/arm920'/f.name
 shutil.copyfile(new if new.exists() else old if old.exists() else original if original.exists() else f,src/f.name)
# Collision poison is stronger than the production RAM used by real CPU runs.
shutil.copyfile(ROOT/'tests/cpu/cache_probe_retime/rtl/ngage_bram.v',src/'ngage_bram.v')
shutil.copyfile(HERE/'pressure.v',out/'test.v')
cp=lambda p:'/work/'+str(p.relative_to(ROOT))
docker=['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',str(ROOT)+':/work','-w','/work','--entrypoint']
def call(cmd,name):
 with (out/name).open('w') as f:r=subprocess.run(cmd,cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
 assert r.returncode==0,str(out/name)
files=[*sorted(src.glob('*')) ,out/'test.v']
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
manifest={str(f.relative_to(ROOT)):sha(f) for f in files}
(out/'source.json').write_text(json.dumps(manifest,indent=2)+'\n')
call(docker+['verilator','jotego/simulator:arm64','--binary','--timing','--assert','-j','3','-Wno-fatal','-Wno-lint','--top-module','test','--Mdir',cp(out/'obj'),*[cp(f) for f in files]],'build.log')
for i in range(2):call(docker+[cp(out/'obj/Vtest'),'jotego/simulator:arm64'],f'run-{i}.log')
events=lambda p:[l for l in p.read_text().splitlines() if l.startswith(('PRESSURE_CASE','PASS pressure'))]
assert events(out/'run-0.log')==events(out/'run-1.log') and any(l.startswith('PASS pressure') for l in events(out/'run-0.log'))
assert manifest=={str(f.relative_to(ROOT)):sha(f) for f in files}
(out/'result.json').write_text(json.dumps(dict(status='PASS',events=events(out/'run-0.log'),source=manifest),indent=2)+'\n')
print('\n'.join(events(out/'run-0.log')))
