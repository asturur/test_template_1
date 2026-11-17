#!/usr/bin/env python3
from pathlib import Path
from setup import ROOT,HERE
p=ROOT/'tests/cpu/cpu_late_operand/bench.py'
s=p.read_text().replace('cpu-late-operand','tlb-area')
exec(compile(s,str(p),'exec'))
