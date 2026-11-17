#!/usr/bin/env python3
"""Unchanged 4E store stream and focused 4F late-data hazards on the real CPU."""
from setup import *
import sys
from hazards import qualify
safety='--safety' in sys.argv
if safety:sys.argv.remove('--safety')
path=ROOT/'tests/cpu/cpu_store_credit/run.py'
text=path.read_text().replace('build/sim/cpu-store-credit','build/sim/cpu-store-second').replace('tests/cpu/cpu_store_credit/observe.vh','tests/cpu/cpu_store_second/observe.vh')
text=text.replace('assert text.count(old)==1', 'new="overlay(source,not a.control)"\nassert text.count(old)==1')
text=text.replace("{'__file__':__file__,'__name__':'__main__'}","dict(globals(),__file__=__file__,__name__='__main__')")
text=text.replace("assert text.count(old)==1", "text=text.replace(\"'-DNGAGE_RUNTIME_TRACE',\",\"*([] if a.control else ['-DBENCH_LOADPAIR','-DBENCH_STORE_LATE','-DBENCH_STORE_SECOND']),'-DNGAGE_RUNTIME_TRACE',\")\nassert text.count(old)==1")
# Expand the source wrapper before it executes the common stream runner.
text=text.replace("text=path.read_text()", "text=path.read_text()\ntext=text.replace(\"program_sha256=sha(out/\",\"runtime_args=list(a.arg),fixture_sha256={f.name:sha(f) for f in HERE.iterdir() if f.suffix in ['.v','.vh']},program_sha256=sha(out/\")\ntext=text.replace(\"exe=ROOT/a.reuse/'obj/Vbench'\",\"assert old['fixture_sha256']==manifest['fixture_sha256'],'fixture include changed'\\n exe=ROOT/a.reuse/'obj/Vbench'\")\ntext=text.replace(\"manifest['executable_sha256']=sha(exe)\",\"(out/'fixture').mkdir()\\nfor f in HERE.iterdir():\\n if f.suffix in ['.v','.vh']:shutil.copyfile(f,out/'fixture'/f.name)\\nmanifest['executable_sha256']=sha(exe)\")")
if safety:text=text.replace("exec(compile(text,str(Path(__file__)),","text=qualify(text)\nexec(compile(text,str(Path(__file__)),")
exec(compile(text,str(Path(__file__)),'exec'),dict(globals(),__file__=__file__,__name__='__main__'))
