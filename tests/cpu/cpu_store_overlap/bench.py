#!/usr/bin/env python3
"""Matched original fixed-work payload runner on Stop 3C versus Step 4A."""
from pathlib import Path
import argparse,sys,types,shutil
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--control',action='store_true');a,rest=p.parse_known_args()
sys.path.insert(0,str(ROOT/'tests/cpu/spmark_payload'))
path=ROOT/'tests/cpu/cache_probe_retime/payload_run.py'
module=types.ModuleType('store_overlap_payload');module.__file__=str(path)
source=path.read_text().replace("tb = Path(__file__).with_name('tb.v')", "tb = ROOT/'tests/cpu/cpu_store_overlap/payload_tb.v'")
exec(compile(source,str(path),'exec'),module.__dict__)
original=module.support
def support():
 b=original();freeze=b.snapshot
 def snapshot(destination,revision=None,root=ROOT):
  old=freeze(destination,'9c948da8da413a882e0fe8e559c380ea0cadabf4',root)
  for f in (ROOT/'tests/cpu/cache_probe_retime/rtl').glob('cache*.sv'):shutil.copyfile(f,destination/'rtl/arm920'/f.name)
  if not a.control:
   for f in (HERE/'rtl').rglob('*'):
    if f.is_file():shutil.copyfile(f,destination/'rtl'/f.relative_to(HERE/'rtl'))
  return b.source_manifest(destination,old['commit'],'Step4A-control' if a.control else 'Step4A-candidate')
 b.snapshot=snapshot;return b
module.support=support
sys.argv=[str(path),*rest]
module.main()
