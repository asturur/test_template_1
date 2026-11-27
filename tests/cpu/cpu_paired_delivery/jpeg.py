#!/usr/bin/env python3
"""Existing original Thumb JPEG block on pinned5C versus paired delivery."""
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
  r=b.source_manifest(destination,old['commit'],'5D-JPEG-fixed5C' if a.control else '5D-JPEG-candidate')
  return r
 b.snapshot=snapshot;return b
common.support=support
path=ROOT/'tests/cpu/cache_probe_retime/jpeg_run.py'
text=path.read_text().replace("sys.path.insert(0,str(ROOT/'scratch/spmark-jpeg-profile-20261115'))", "sys.path.insert(0,str(ROOT/'tests/cpu/cache_probe_retime'))")
text=text.replace("'-j','3'","'-j','1'")
text=text.replace('def cases():return all_cases()', 'def cases():return all_cases()[:1]')
sys.argv=[str(path),*rest]
exec(compile(text,str(path),'exec'),dict(__file__=str(path),__name__='__main__'))
