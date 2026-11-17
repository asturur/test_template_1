#!/usr/bin/env python3
import sys
from setup import ROOT,HERE
p=ROOT/'tests/cpu/cpu_load_lookup/bench.py'
s=p.read_text().replace("choices=['5f','p1','lookup']","choices=['late']").replace("default='lookup'","default='late'")
s=s.replace('cpu-load-lookup','cpu-late-operand')
s=s.replace("if a.variant=='lookup':","if a.variant in ['lookup','late']:")
exec(compile(s,str(p),'exec'))
