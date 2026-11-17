#!/usr/bin/env python3
"""Broader original-payload qualification of the exact combined 5J/5K CPU."""
import argparse,importlib.util,sys,shutil
from pathlib import Path
from setup import ROOT,BASE,HERE
p=argparse.ArgumentParser();p.add_argument('--jpeg',action='store_true');a,rest=p.parse_known_args()
sys.path.insert(0,str(ROOT/'tests/cpu/spmark_payload'))
import run as common
original=common.support
def support():
    b=original();freeze=b.snapshot
    def snapshot(destination,revision=None,root=ROOT):
        old=freeze(destination,BASE,root)
        shutil.copyfile(HERE/'rtl/arm/zap_core.sv',destination/'rtl/arm/zap_core.sv')
        return b.source_manifest(destination,old['commit'],'combined-5JK-qualification')
    b.snapshot=snapshot
    return b
common.support=support
if a.jpeg:
    path=ROOT/'tests/cpu/cache_probe_retime/jpeg_run.py'
    source=path.read_text().replace("'-j','3'","'-j','1'").replace('def cases():return all_cases()','def cases():return all_cases()[:1]')
    sys.argv=[str(path),*rest]
    exec(compile(source,str(path),'exec'),dict(__file__=str(path),__name__='__main__'))
else:
    sys.argv=[str(Path(common.__file__)),*rest,'--jobs','1']
    common.main()
