#!/usr/bin/env python3
"""Focused PC handoff ownership/priority regression on the real writeback module."""
from setup import *
import argparse,subprocess
p=argparse.ArgumentParser();p.add_argument('name');a=p.parse_args()
out=ROOT/'build/sim/cpu-issue-recovery'/a.name;out.mkdir(parents=True,exist_ok=False)
(out/'result.json').write_text('{"status":"INCOMPLETE"}\n')
source=out/'source';source.mkdir()
files=[HERE/'rtl/arm/zap_writeback.sv',HERE/'redirect_test.v']+[ROOT/'rtl/arm'/f for f in ['zap_btb.sv','zap_ram_simple_nopipe.sv','zap_register_file.sv']]
for f in files:shutil.copyfile(f,source/f.name)
files=list(sorted(source.iterdir()))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
hashes={str(f.relative_to(ROOT)):sha(f) for f in files}
(out/'source.json').write_text(json.dumps(hashes,indent=2)+'\n')
cp=lambda p:'/work/'+str(p.relative_to(ROOT))
docker=['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',str(ROOT)+':/work','-w','/work','--entrypoint']
def call(cmd,log):
 with (out/log).open('w') as f:r=subprocess.run(cmd,cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
 if r.returncode:
  (out/'result.json').write_text(json.dumps(dict(status='FAIL',exit_code=r.returncode,failed_log=log,source=hashes),indent=2)+'\n')
  raise RuntimeError(str(out/log))
call(docker+['verilator','jotego/simulator:arm64','--binary','--timing','--assert','-j','4','-Wno-fatal','-Wno-lint','-I/work/rtl/arm','--top-module','test','--Mdir',cp(out/'obj'),*[cp(f) for f in files]],'build.log')
for i in range(2):call(docker+[cp(out/'obj/Vtest'),'jotego/simulator:arm64'],f'run-{i}.log')
events=lambda p:[l for l in p.read_text().splitlines() if l.startswith(('REDIRECT_CASE','PASS redirect'))]
assert events(out/'run-0.log')==events(out/'run-1.log') and any(l.startswith('PASS redirect') for l in events(out/'run-0.log'))
assert hashes=={str(f.relative_to(ROOT)):sha(f) for f in files}
(out/'result.json').write_text(json.dumps(dict(status='PASS',events=events(out/'run-0.log'),source=hashes),indent=2)+'\n')
print('\n'.join(events(out/'run-0.log')))
