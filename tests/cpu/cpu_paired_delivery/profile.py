#!/usr/bin/env python3
"""Reuse the existing ARMv4T profile, including scalar MUL/MLA owner transitions."""
from pathlib import Path
import argparse,json,hashlib,subprocess,shutil,sys
ROOT=Path(__file__).resolve().parents[3]
p=argparse.ArgumentParser();p.add_argument('name');p.add_argument('--build',type=Path,required=True);a=p.parse_args();out=ROOT/'build/sim/cpu-paired-delivery'/a.name;out.mkdir(parents=True,exist_ok=False)
build=ROOT/a.build;m=json.loads((build/'manifest.json').read_text());ref=out/'reference';ref.mkdir()
for name,h in m['source']['files'].items():assert hashlib.sha256((build/'source'/name).read_bytes()).hexdigest()==h,name
for directory in ['arm','arm920']:
 for f in (build/'source/rtl'/directory).iterdir():
  if f.is_file():shutil.copyfile(f,ref/f.name)
path=ROOT/'tests/cpu/armv4t_profile/run.py';text=path.read_text().replace('--binary -j 4 --timing','--binary -j 1 --timing').replace('--rm --network none','--rm --pull=never --network none')
sys.argv=[str(path),'--out',str((out/'profile').relative_to(ROOT)),'--profile-only','--reference-dir',str(ref.relative_to(ROOT))]
exec(compile(text,str(path),'exec'),dict(__file__=str(path),__name__='__main__'))
r=json.loads((out/'profile/result.json').read_text());assert r['status']=='PASS'
(out/'result.json').write_text(json.dumps(dict(status='PASS',source_id=m['source']['source_id'],existing_profile=r),indent=2)+'\n')
print('PASS unchanged ARMv4T profile, including MUL/MLA/long-multiply legal controls')
