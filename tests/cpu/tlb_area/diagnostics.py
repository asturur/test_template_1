#!/usr/bin/env python3
"""Actual-CPU translation/CP15/ordering acceptance of the banked area candidate."""
import hashlib,json,shutil
from pathlib import Path
from setup import ROOT
p=ROOT/'tests/cpu/cpu_store_postindex/diagnostics.py'
s=p.read_text().replace('from setup import *','').replace('cpu-store-postindex','tlb-area')
cases=['smoke','mmu_fcse','mmu_fetch','tlb_lockdown','tlb_permission_reuse','tlb_two_mapping','icache_prefetch_translated','icache_tlb_write_order','cache_tlb_write_order','prefetch_fault','btb_return']
s=s.replace("['smoke','mmu_fcse','prefetch_fault','btb_return']",repr(cases))
s=s.replace("a=p.parse_args()", "p.add_argument('--reuse-exe',type=Path);a=p.parse_args()")
s=s.replace("m.execute(docker(cmd),out/'build.log')", """if a.reuse_exe:
 exe=ROOT/a.reuse_exe
 prior=json.loads((exe.parent/'ngage-build-manifest.json').read_text())
 assert prior['source_id']==manifest['source']['source_id'] and prior['binary_sha256']==sha(exe)
 for f,h in prior['inputs'].items():assert sha(ROOT/f)==h
 obj.mkdir()
else:m.execute(docker(cmd),out/'build.log')""")
exec(compile(s,str(p),'exec'))
