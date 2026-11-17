#!/usr/bin/env python3
"""Original fixed-work payloads on pinned accepted5D versus rejected BTB delivery."""
from setup import *
import argparse,sys,types
p=argparse.ArgumentParser();p.add_argument('--control',action='store_true');a,rest=p.parse_known_args()

sys.path.insert(0,str(ROOT/'tests/cpu/spmark_payload'))
path=ROOT/'tests/cpu/cache_probe_retime/payload_run.py';module=types.ModuleType('issue_payload');module.__file__=str(path)
source=path.read_text().replace("tb = Path(__file__).with_name('tb.v')", "tb = ROOT/'tests/cpu/cpu_target_delivery/payload_tb.v'")
source=source.replace("'-DNGAGE_RUNTIME_TRACE',","'-DNGAGE_RUNTIME_TRACE','-DBENCH_STORE_LATE','-DBENCH_STORE_SECOND',")
exec(compile(source,str(path),'exec'),module.__dict__)
original=module.support
def support():
 b=original();freeze=b.snapshot
 def snapshot(destination,revision=None,root=ROOT):
  old=freeze(destination,BASE,root)
  overlay(destination,not a.control)
  # Keep all passive observer inputs with the frozen executable provenance.
  fixtures=destination.parent/'fixture';fixtures.mkdir(exist_ok=True)
  inputs=list(HERE.glob('*.v'))+list(HERE.glob('*.vh'))
  inputs+=list((ROOT/'tests/cpu/cpu_frontend_delivery').glob('*.vh'))
  hashes={}
  for f in inputs:
   rel=f.relative_to(ROOT);target=fixtures/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(f,target)
   hashes[str(rel)]=hashlib.sha256(f.read_bytes()).hexdigest()
  (destination.parent/'fixture.json').write_text(json.dumps(hashes,indent=2)+'\n')
  result=b.source_manifest(destination,old['commit'],'5E-fixed5D' if a.control else '5E-candidate')
  return result
 b.snapshot=snapshot;return b
module.support=support
sys.argv=[str(path),*rest];module.main()
