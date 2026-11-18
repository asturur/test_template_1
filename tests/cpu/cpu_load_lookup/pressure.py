#!/usr/bin/env python3
"""Exercise the unchanged 5F cache guards with arbitrary early private hints."""
import argparse,hashlib,json,shutil,subprocess
from setup import ROOT,HERE

p=argparse.ArgumentParser();p.add_argument('name');a=p.parse_args()
out=ROOT/'build/sim/cpu-load-lookup'/a.name;out.mkdir(parents=True,exist_ok=False)
src=out/'source';src.mkdir()
for f in (ROOT/'rtl/arm920').glob('*.sv'):shutil.copyfile(f,src/f.name)
shutil.copyfile(ROOT/'tests/cpu/cache_probe_retime/rtl/ngage_bram.v',src/'ngage_bram.v')
fixture=(ROOT/'tests/cpu/cpu_load_overlap/pressure.v').read_text()
fixture=fixture.replace('.external_permit(1\'b1),', ".external_permit(1'b1),\n      .private_write(wr),")
(out/'test.v').write_text(fixture)
cp=lambda p:'/work/'+str(p.relative_to(ROOT))
docker=['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',str(ROOT)+':/work','-w','/work','--entrypoint']
def call(cmd,name):
    with (out/name).open('w') as f:r=subprocess.run(cmd,cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
    assert r.returncode==0,str(out/name)
files=[*sorted(src.iterdir()),out/'test.v'];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
manifest={str(f.relative_to(ROOT)):sha(f) for f in files}
(out/'source.json').write_text(json.dumps(manifest,indent=2)+'\n')
call(docker+['verilator','jotego/simulator:arm64','--binary','--timing','--assert','-j','1','-Wno-fatal','-Wno-lint',
             '--top-module','test','--Mdir',cp(out/'obj'),*[cp(f) for f in files]],'build.log')
for i in range(2):call(docker+[cp(out/'obj/Vtest'),'jotego/simulator:arm64'],f'run-{i}.log')
def events(p):return [l for l in p.read_text().splitlines() if l.startswith(('PRESSURE_CASE','PASS pressure'))]
assert events(out/'run-0.log')==events(out/'run-1.log')
assert any(l.startswith('PASS pressure') for l in events(out/'run-0.log'))
assert manifest=={str(f.relative_to(ROOT)):sha(f) for f in files}
(out/'result.json').write_text(json.dumps(dict(status='PASS',events=events(out/'run-0.log'),source=manifest,
                                             executable_sha256=sha(out/'obj/Vtest')),indent=2)+'\n')
print('\n'.join(events(out/'run-0.log')))
