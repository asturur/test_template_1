#!/usr/bin/env python3
"""Original fixed-work payloads on exact5B versus the isolated product bypass."""
from setup import *
import argparse,sys,types
p=argparse.ArgumentParser();p.add_argument('--control',action='store_true');a,rest=p.parse_known_args()

sys.path.insert(0,str(ROOT/'tests/cpu/spmark_payload'))
path=ROOT/'tests/cpu/cache_probe_retime/payload_run.py';module=types.ModuleType('issue_payload');module.__file__=str(path)
source=path.read_text().replace("tb = Path(__file__).with_name('tb.v')", "tb = ROOT/'tests/cpu/cpu_product_bypass/payload_tb.v'")
source=source.replace("'-DNGAGE_RUNTIME_TRACE',","'-DNGAGE_RUNTIME_TRACE','-DBENCH_STORE_LATE','-DBENCH_STORE_SECOND',")
exec(compile(source,str(path),'exec'),module.__dict__)
original=module.support
def support():
 b=original();freeze=b.snapshot
 def snapshot(destination,revision=None,root=ROOT):
  old=freeze(destination,'9c948da8da413a882e0fe8e559c380ea0cadabf4',root)
  overlay(destination,not a.control)
  result=b.source_manifest(destination,old['commit'],'5C-fixed5B' if a.control else '5C-candidate')
  if a.control:assert result['source_id']==evidence['source_id']
  return result
 b.snapshot=snapshot;return b
module.support=support
sys.argv=[str(path),*rest];module.main()
