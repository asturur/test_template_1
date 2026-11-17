#!/usr/bin/env python3
"""Original six-kernel or Thumb JPEG qualification of the exact Step5L overlay."""
import argparse,sys
from pathlib import Path
from setup import ROOT,BASE,overlay
p=argparse.ArgumentParser();p.add_argument('--jpeg',action='store_true');a,rest=p.parse_known_args()
sys.path.insert(0,str(ROOT/'tests/cpu/spmark_payload'))
import run as common
original=common.support
def support():
    b=original();freeze=b.snapshot
    def snapshot(destination,revision=None,root=ROOT):
        old=freeze(destination,BASE,root);overlay(destination,True)
        return b.source_manifest(destination,old['commit'],'Step5L-qualification')
    b.snapshot=snapshot
    return b
common.support=support
if not a.jpeg:
    sys.argv=[str(Path(common.__file__)),*rest,'--jobs','1']
    common.main()
    raise SystemExit(0)
path=ROOT/'tests/cpu/cache_probe_retime/jpeg_run.py'
s=path.read_text().replace("'-j','3'","'-j','1'").replace('def cases():return all_cases()','def cases():return all_cases()[:1]')
sys.argv=[str(path),*rest]
exec(compile(s,str(path),'exec'),dict(__file__=str(path),__name__='__main__'))
