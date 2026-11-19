#!/usr/bin/env python3
"""Clocks and time of each membench loop (its second run).  table.py RUN.log MHZ"""
import re
import sys

mhz = float(sys.argv[2])
total = 0.0
print(f'{"loop":<10}{"clocks":>10}{"us":>9}{"scalar rd":>11}{"scalar wr":>11}{"lines":>8}{"ddr rd":>8}')
for line in open(sys.argv[1], errors='replace'):
    m = re.match(r'^m?([a-z0-9]+)((?:\[[0-9 ]+\]){4})\s*$', line)
    if not m:
        if line.startswith(('memtest', 'emtest', 'BENCH_END')):
            print(line.rstrip())
        continue
    st = [[int(x) for x in g.split()] for g in re.findall(r'\[([0-9 ]+)\]', m.group(2))]
    d = [b - a for a, b in zip(st[2], st[3])]
    total += d[0] / mhz
    print(f'{m.group(1):<10}{d[0]:>10}{d[0] / mhz:>9.0f}{d[1]:>11}{d[2]:>11}{d[3]:>8}{d[4]:>8}')
if total:
    print(f'{"total":<10}{"":>10}{total:>9.0f}')
