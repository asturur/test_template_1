#!/usr/bin/env python3
from pathlib import Path
from setup import ROOT,HERE
p=ROOT/'tests/cpu/cpu_late_operand/bench.py'
s=p.read_text().replace('cpu-late-operand','cpu-load-admission')
# Reuse the exact observers (including late-arithmetic events), adding the
# registered admission owner state for the bounded schedule.
exec(compile(s,str(p),'exec'))
