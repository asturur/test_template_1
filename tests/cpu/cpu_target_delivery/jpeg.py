#!/usr/bin/env python3
"""Existing original Thumb JPEG block on pinned5D versus rejected BTB delivery."""
from setup import *
import argparse,sys,types
p=argparse.ArgumentParser(add_help=False);p.add_argument('--control',action='store_true');a,rest=p.parse_known_args()
sys.path.insert(0,str(ROOT/'tests/cpu/spmark_payload'))
import run as common
original=common.support
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
  r=b.source_manifest(destination,old['commit'],'5E-JPEG-fixed5D' if a.control else '5E-JPEG-candidate')
  return r
 b.snapshot=snapshot;return b
common.support=support
path=ROOT/'tests/cpu/cache_probe_retime/jpeg_run.py'
text=path.read_text().replace("sys.path.insert(0,str(ROOT/'scratch/spmark-jpeg-profile-20261115'))", "sys.path.insert(0,str(ROOT/'tests/cpu/cache_probe_retime'))")
text=text.replace("'-j','3'","'-j','1'")
text=text.replace("tb=(ROOT/'tests/cpu/cache_probe_retime/tb.v').read_text()", "tb=(ROOT/'tests/cpu/cache_probe_retime/tb.v').read_text().replace('module bench;','module bench;\\n`include \"tests/cpu/cpu_target_delivery/timeline.vh\"')")
text=text.replace("observer_text=observer.read_text()", "observer_text=observer.read_text().replace(' original_prof_sample();',' original_prof_sample(); target_sample();')")
text=text.replace('def cases():return all_cases()', 'def cases():return all_cases()[:1]')
sys.argv=[str(path),*rest]
exec(compile(text,str(path),'exec'),dict(__file__=str(path),__name__='__main__'))
