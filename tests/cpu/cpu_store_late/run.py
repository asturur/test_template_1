#!/usr/bin/env python3
"""Unchanged 4E store stream and focused 4F late-data hazards on the real CPU."""
from setup import *
import sys
from hazards import qualify
safety='--safety' in sys.argv
if safety:sys.argv.remove('--safety')
path=ROOT/'tests/cpu/cpu_store_credit/run.py'
text=path.read_text().replace('build/sim/cpu-store-credit','build/sim/cpu-store-late').replace('tests/cpu/cpu_store_credit/observe.vh','tests/cpu/cpu_store_late/observe.vh')
text=text.replace('assert text.count(old)==1', 'new="overlay(source,not a.control)"\nassert text.count(old)==1')
text=text.replace("{'__file__':__file__,'__name__':'__main__'}","dict(globals(),__file__=__file__,__name__='__main__')")
text=text.replace("assert text.count(old)==1", "text=text.replace(\"'-DNGAGE_RUNTIME_TRACE',\",\"*([] if a.control else ['-DBENCH_LOADPAIR','-DBENCH_STORE_LATE']),'-DNGAGE_RUNTIME_TRACE',\")\nassert text.count(old)==1")
if safety:text=text.replace("exec(compile(text,str(Path(__file__)),","text=qualify(text)\nexec(compile(text,str(Path(__file__)),")
exec(compile(text,str(Path(__file__)),'exec'),dict(globals(),__file__=__file__,__name__='__main__'))
