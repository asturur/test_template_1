#!/usr/bin/env python3
"""Original payloads and exact store ownership on fixed 4E versus the 4F prototype."""
from setup import *
import argparse,sys,types
p=argparse.ArgumentParser();p.add_argument('--control',action='store_true');a,rest=p.parse_known_args()

sys.path.insert(0,str(ROOT/'tests/cpu/spmark_payload'))
path=ROOT/'tests/cpu/cache_probe_retime/payload_run.py';module=types.ModuleType('issue_payload');module.__file__=str(path)
source=path.read_text().replace("tb = Path(__file__).with_name('tb.v')", "tb = ROOT/'tests/cpu/cpu_store_second/payload_tb.v'")
if not a.control:source=source.replace("'-DNGAGE_RUNTIME_TRACE',","'-DNGAGE_RUNTIME_TRACE','-DBENCH_STORE_LATE','-DBENCH_STORE_SECOND',")
exec(compile(source,str(path),'exec'),module.__dict__)
original=module.support
def support():
 b=original();freeze=b.snapshot
 def snapshot(destination,revision=None,root=ROOT):
  old=freeze(destination,'9c948da8da413a882e0fe8e559c380ea0cadabf4',root)
  overlay(destination,not a.control)
  result=b.source_manifest(destination,old['commit'],'4G-fixed4F' if a.control else '4G-candidate')
  if a.control:assert result['source_id']==evidence['candidate_source_id']
  return result
 b.snapshot=snapshot;return b
module.support=support
sys.argv=[str(path),*rest];module.main()
