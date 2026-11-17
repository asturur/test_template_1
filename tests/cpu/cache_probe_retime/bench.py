#!/usr/bin/env python3
"""Run matched original CPU workloads from an explicit base+overlay snapshot."""
from pathlib import Path
import argparse,sys,importlib.util,runpy,shutil
ROOT=Path(__file__).resolve().parents[3]
p=argparse.ArgumentParser();p.add_argument('--kind',choices=['six','jpeg'],required=True);p.add_argument('--variant',choices=['control','candidate'],required=True);p.add_argument('--name',required=True);a,rest=p.parse_known_args()
sys.path.insert(0,str(ROOT/'tests/cpu/spmark_payload'))
P=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('run',P/'payload_run.py');common=importlib.util.module_from_spec(spec);sys.modules['run']=common;spec.loader.exec_module(common)
original=common.support
closure=P/'rtl' if a.variant=='candidate' else ROOT/'tests/cpu/cache_resident_qualification/rtl'
def support():
 b=original();freeze=b.snapshot
 def snapshot(destination,revision=None,root=ROOT):
  old=freeze(destination,'9c948da8da413a882e0fe8e559c380ea0cadabf4',root)
  for n in ['cache_access.sv','cache_bank.sv','cache_tags.sv','cache_adapter.sv']:
   if (closure/n).exists():shutil.copyfile(closure/n,destination/'rtl/arm920'/n)
  return b.source_manifest(destination,old['commit'],'probe-retime-'+a.variant)
 b.snapshot=snapshot;return b
common.support=support
sys.argv=[str(P/'payload_run.py'),'--name',a.name,*rest]
if a.kind=='six':common.main()
else:runpy.run_path(str(P/'jpeg_run.py'),run_name='__main__')
