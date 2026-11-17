#!/usr/bin/env python3
from setup import ROOT
p=ROOT/'tests/cpu/cpu_late_operand/safety.py'
exec(compile(p.read_text(),str(p),'exec'))
