#!/usr/bin/env python3
"""Reuse the unchanged 4A guest/oracles with fixed 4A control and one spare credit."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[3]
import hashlib,json
fixed=json.loads((ROOT/'docs/evidence/cpu-store-overlap-20261116.json').read_text())
assert fixed['candidate_source_id']=='dcbc85875b34ffaeafe289cea6ecd6e806ec37878fdbb5a8c85f7ded0c93edcb', '4A control identity changed'
for name,value in fixed['overlay_sha256'].items():
 assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==value,name
path=ROOT/'tests/cpu/cpu_store_overlap/run.py'
text=path.read_text()
stress='--stress' in sys.argv
if stress:sys.argv.remove('--stress')
if stress:
 text=text.replace(' ldr r0,[r12]\n.global forbidden_fault_store', ' str r1,[r10,#16]\n str r2,[r10,#20]\n ldr r0,[r12]\n.global forbidden_fault_store')
 text=text.replace('after_fault:\n ldr r0,[r10]', 'after_fault:\n ldr r0,[r10,#16]\n cmp r0,r1\n bne fail\n ldr r0,[r10,#20]\n cmp r0,r2\n bne fail\n ldr r0,[r10]')
 text=text.replace('irq_marker: nop', 'irq_marker: str r1,[r10,#8]\n str r2,[r10,#12]')
 text=text.replace('after_irq:\n cmp r9,#1', 'after_irq:\n ldr r0,[r10,#8]\n cmp r0,r1\n bne fail\n ldr r0,[r10,#12]\n cmp r0,r2\n bne fail\n cmp r9,#1')
 text=text.replace('stores_end:\n strb r1', 'stores_end:\n ldr r0,[r10,#60]\n cmp r0,r3\n bne fail\n strb r1')
 text=text.replace("for repeat in range(2):", "a.arg.append('+stress=1')\nfor repeat in range(2):")

old="if not a.control:\n for f in (HERE/'rtl').rglob('*'):\n  if f.is_file():shutil.copyfile(f,source/'rtl'/f.relative_to(HERE/'rtl'))"
new="""for f in (ROOT/'tests/cpu/cpu_store_overlap/rtl').rglob('*.sv'):
 shutil.copyfile(f,source/'rtl'/f.relative_to(ROOT/'tests/cpu/cpu_store_overlap/rtl'))
if not a.control:
 for f in (HERE/'rtl').rglob('*.sv'):
  shutil.copyfile(f,source/'rtl'/f.relative_to(HERE/'rtl'))"""
assert text.count(old)==1
text=text.replace(old,new).replace("build/sim/cpu-store-overlap","build/sim/cpu-store-credit").replace('tests/cpu/cpu_store_overlap/observe.vh','tests/cpu/cpu_store_credit/observe.vh')
exec(compile(text,str(Path(__file__)),'exec'),{'__file__':__file__,'__name__':'__main__'})
