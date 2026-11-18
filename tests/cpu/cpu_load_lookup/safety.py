#!/usr/bin/env python3
"""Use the unchanged real-CPU 5J safety guest on the selected 5K build."""
from pathlib import Path
from setup import ROOT
path=ROOT/'tests/cpu/cpu_load_pipeline/safety.py'
source=path.read_text().replace('after_flush:\n', '''after_flush:
 ldr r0,=0x80001000
 ldr r1,=0x7654abcd
 str r1,[r0,#8]
 ldr r2,[r0,#8]
 cmp r2,r1
 bne fail
 ldr r1,=0xabcd7654
 str r1,[r0,#8]
 add r3,r3,#1
 add r3,r3,#1
 ldr r2,[r0,#8]
 cmp r2,r1
 bne fail
''')
source=source.replace("'flushed MMIO load excluded'", "'flushed MMIO load excluded','fresh load after same-line stores with and without independent work'")
exec(compile(source,str(path),'exec'))
