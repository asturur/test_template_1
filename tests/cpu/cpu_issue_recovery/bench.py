#!/usr/bin/env python3
"""Stage/owner traces and original payload work on fixed 4D versus one CPU change."""
from setup import *
import argparse,sys,types
p=argparse.ArgumentParser();p.add_argument('--control',action='store_true');p.add_argument('--four-c',action='store_true');a,rest=p.parse_known_args()
assert not(a.control and a.four_c)
sys.path.insert(0,str(ROOT/'tests/cpu/spmark_payload'))
path=ROOT/'tests/cpu/cache_probe_retime/payload_run.py';module=types.ModuleType('issue_payload');module.__file__=str(path)
source=path.read_text().replace("tb = Path(__file__).with_name('tb.v')", "tb = ROOT/'tests/cpu/cpu_issue_recovery/payload_tb.v'")
exec(compile(source,str(path),'exec'),module.__dict__)
original=module.support
def support():
 b=original();freeze=b.snapshot
 def snapshot(destination,revision=None,root=ROOT):
  old=freeze(destination,'9c948da8da413a882e0fe8e559c380ea0cadabf4',root)
  overlay(destination,not(a.control or a.four_c),a.four_c)
  result=b.source_manifest(destination,old['commit'],'4E-4C-trace' if a.four_c else '4E-fixed4D' if a.control else '4E-candidate')
  if a.control:assert result['source_id']==evidence['candidate_source_id']
  return result
 b.snapshot=snapshot;return b
module.support=support
sys.argv=[str(path),*rest];module.main()
