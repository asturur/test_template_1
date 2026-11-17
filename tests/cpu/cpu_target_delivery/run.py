#!/usr/bin/env python3
"""Existing ordered-store, fault/IRQ and late-data guest on pinned5C/5D."""
from setup import *
import sys
sys.path.insert(0,str(ROOT/'tests/cpu/cpu_frontend_delivery'))
from hazards import qualify
safety='--safety' in sys.argv
if safety:sys.argv.remove('--safety')
text=(ROOT/'tests/cpu/cpu_store_overlap/run.py').read_text()
old="if not a.control:\n for f in (HERE/'rtl').rglob('*'):\n  if f.is_file():shutil.copyfile(f,source/'rtl'/f.relative_to(HERE/'rtl'))"
assert text.count(old)==1
text=text.replace(old,'overlay(source,not a.control)')
text=text.replace("'9c948da8da413a882e0fe8e559c380ea0cadabf4'",'BASE')
text=text.replace('build/sim/cpu-store-overlap','build/sim/cpu-target-delivery')
text=text.replace('tests/cpu/cpu_store_overlap/observe.vh','tests/cpu/cpu_frontend_delivery/observe.vh')
text=text.replace("'-DNGAGE_RUNTIME_TRACE',","'-DBENCH_LOADPAIR','-DBENCH_STORE_LATE','-DBENCH_STORE_SECOND','-DNGAGE_RUNTIME_TRACE',")
text=text.replace("'-j','4'","'-j','1'")
if safety:text=qualify(text)
exec(compile(text,str(Path(__file__)),'exec'),dict(globals(),__file__=__file__,__name__='__main__'))
