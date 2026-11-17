#!/usr/bin/env python3
"""Matched original payload: final 4C versus bounded 4D read-port overlap."""
from setup import *
import argparse,sys,types
p=argparse.ArgumentParser();p.add_argument('--control',action='store_true');a,rest=p.parse_known_args()
sys.path.insert(0,str(ROOT/'tests/cpu/spmark_payload'))
path=ROOT/'tests/cpu/cache_probe_retime/payload_run.py'
module=types.ModuleType('load_overlap_payload');module.__file__=str(path)
source=path.read_text().replace("tb = Path(__file__).with_name('tb.v')", "tb = ROOT/'tests/cpu/cpu_load_overlap/payload_tb.v'")
exec(compile(source,str(path),'exec'),module.__dict__)
original=module.support
def support():
 b=original();freeze=b.snapshot
 def snapshot(destination,revision=None,root=ROOT):
  old=freeze(destination,'9c948da8da413a882e0fe8e559c380ea0cadabf4',root)
  overlay(destination,not a.control)
  result=b.source_manifest(destination,old['commit'],'4D-final4C-control' if a.control else '4D-candidate')
  if a.control:assert result['source_id']=='7f3ce0f6fdba8b358a57acc36fa144177cb51fd15e0dd4a1eb216c5b3463094e'
  return result
 b.snapshot=snapshot;return b
module.support=support
sys.argv=[str(path),*rest]
module.main()
