#!/usr/bin/env python3
"""Original fixed-work payloads on pinned accepted5C versus paired delivery."""
from setup import *
import argparse,sys,types
p=argparse.ArgumentParser();p.add_argument('--control',action='store_true');a,rest=p.parse_known_args()

sys.path.insert(0,str(ROOT/'tests/cpu/spmark_payload'))
path=ROOT/'tests/cpu/cache_probe_retime/payload_run.py';module=types.ModuleType('issue_payload');module.__file__=str(path)
source=path.read_text().replace("tb = Path(__file__).with_name('tb.v')", "tb = ROOT/'tests/cpu/cpu_paired_delivery/payload_tb.v'")
source=source.replace("'-DNGAGE_RUNTIME_TRACE',","'-DNGAGE_RUNTIME_TRACE','-DBENCH_STORE_LATE','-DBENCH_STORE_SECOND',")
exec(compile(source,str(path),'exec'),module.__dict__)
original=module.support
def support():
 b=original();freeze=b.snapshot
 def snapshot(destination,revision=None,root=ROOT):
  old=freeze(destination,BASE,root)
  overlay(destination,not a.control)
  result=b.source_manifest(destination,old['commit'],'5D-fixed5C' if a.control else '5D-candidate')
  return result
 b.snapshot=snapshot;return b
module.support=support
sys.argv=[str(path),*rest];module.main()
