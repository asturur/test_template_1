#!/usr/bin/env python3
"""Real predecode classification plus the existing return/hold/clear checks."""
from setup import *
import argparse
p=argparse.ArgumentParser();p.add_argument('name');a=p.parse_args()
out=ROOT/'build/sim/cpu-store-postindex'/a.name;out.mkdir(parents=True,exist_ok=False)
(out/'result.json').write_text('{"status":"INCOMPLETE"}\n')
source=out/'source';source.mkdir()
files=[HERE/'rtl/arm/zap_predecode_main.sv',HERE/'classify_test.v']+[
 ROOT/'rtl/arm'/n for n in ['zap_predecode_coproc.sv','zap_predecode_uop_sequencer.sv','zap_ones_counter.sv']]
for f in files:shutil.copyfile(f,source/f.name)
inputs=list(source.iterdir());hashes={str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in inputs}
cp=lambda f:'/work/'+str(f.relative_to(ROOT))
docker=['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',str(ROOT)+':/work','-w','/work','--entrypoint']
def call(cmd,log):
 with (out/log).open('w') as f:r=subprocess.run(cmd,cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
 if r.returncode:
  (out/'result.json').write_text(json.dumps(dict(status='FAIL',failed_log=log,source=hashes),indent=2)+'\n');raise RuntimeError(out/log)
call(docker+['verilator','jotego/simulator:arm64','--binary','--timing','--assert','-j','1','-Wno-fatal','-Wno-lint','-I/work/rtl/arm','--top-module','test','--Mdir',cp(out/'obj'),*[cp(f) for f in inputs]],'build.log')
for n in range(2):call(docker+[cp(out/'obj/Vtest'),'jotego/simulator:arm64'],f'run-{n}.log')
events=lambda n:[s for s in (out/f'run-{n}.log').read_text().splitlines() if s.startswith('PASS')]
assert events(0)==events(1) and any('vectors=12288' in e for e in events(0))
(out/'result.json').write_text(json.dumps(dict(status='PASS',events=events(0),source=hashes),indent=2)+'\n')
print('\n'.join(events(0)))
