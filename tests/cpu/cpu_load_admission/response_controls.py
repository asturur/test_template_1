#!/usr/bin/env python3
from setup import ROOT
p=ROOT/'tests/cpu/cpu_late_operand/response_controls.py'
s=p.read_text().replace('cpu-late-operand','cpu-load-admission').replace('step5l-response-01','step5m-response-01')
exec(compile(s,str(p),'exec'))
