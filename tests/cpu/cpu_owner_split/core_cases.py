#!/usr/bin/env python3
"""Reuse actual core/SWP fixtures in distinct outputs on an exact frozen source."""
from pathlib import Path
import argparse,subprocess,os,json,re,hashlib,shutil
ROOT=Path(__file__).resolve().parents[3]
p=argparse.ArgumentParser();p.add_argument('name');p.add_argument('--build',type=Path,required=True);a=p.parse_args()
out=ROOT/'build/sim/cpu-owner-split'/a.name;out.mkdir(parents=True,exist_ok=False)
build=ROOT/a.build;m=json.loads((build/'manifest.json').read_text())
for f,h in m['source']['files'].items():assert hashlib.sha256((build/'source'/f).read_bytes()).hexdigest()==h,f
reference=out/'reference';reference.mkdir()
for directory in ['arm','arm920']:
 for f in (build/'source/rtl'/directory).iterdir():
  if f.is_file():shutil.copyfile(f,reference/f.name)
(out/'source.json').write_text(json.dumps({str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in reference.iterdir()},indent=2)+'\n')
rows=[]
cases=[('completion_overlap',dict(CPU_RUN_ARGS='+completion_overlap_check',CPU_LOAD_FORWARD_CHECK='1')),('swp_basic',{}),('swp_cached',{}),('swp_bufferable',{}),('swp_read_abort',dict(CPU_FAULT_ADDR='80001000',CPU_SWP_ABORT='1')),('swp_mmu_abort',{}),('swp_irq',{}),('swp_cached_irq',{})]
for case,extra in cases:
 d=out/case;d.mkdir();rel=str(d.relative_to(ROOT));script=(ROOT/'tests/cpu/core/sim.sh').read_text()
 script=re.sub(r'^root=.*$', 'root='+str(ROOT),script,flags=re.M)
 script=script.replace('build/sim/unit-core',rel).replace('tests/cpu/core/test.sv',rel+'/test.sv').replace('--rm --network none','--rm --pull=never --network none').replace('--binary --timing','--binary -j 3 --timing')
 tb=(ROOT/'tests/cpu/core/test.sv').read_text().replace('build/sim/unit-core',rel).replace('module test;','module test;\n`include "tests/cpu/cpu_owner_split/owner.vh"',1)
 (d/'test.sv').write_text(tb);(d/'run.sh').write_text(script)
 env=dict(os.environ,CPU_PROGRAM=case,CPU_REFERENCE_DIR=str(reference.relative_to(ROOT)),**extra)
 with (d/'driver.log').open('w') as f:r=subprocess.run(['sh',str(d/'run.sh')],cwd=ROOT,env=env,stdout=f,stderr=subprocess.STDOUT)
 assert r.returncode==0,str(d/'driver.log')
 logs={str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in d.glob('run-*.log')}
 assert len(logs)==2
 [f.unlink() for f in d.iterdir() if f.suffix in ['.gch','.cpp','.h','.a','.d','.o','.mk']]
 rows.append(dict(case=case,status='PASS',logs=logs));print('PASS',case,flush=True)
 (out/'result.json').write_text(json.dumps(dict(status='RUNNING',source_id=m['source']['source_id'],rows=rows),indent=2)+'\n')
(out/'result.json').write_text(json.dumps(dict(status='PASS',source_id=m['source']['source_id'],rows=rows),indent=2)+'\n')
