#!/usr/bin/env python3
"""Reuse the 4B real-CPU store/drain and peak-fault/load oracles unchanged."""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[3]
fixed=json.loads((ROOT/'docs/evidence/cpu-store-credit-20261116.json').read_text())
assert hashlib.sha256((ROOT/'tests/cpu/cpu_store_credit/rtl/arm920/cache_adapter.sv').read_bytes()).hexdigest()==fixed['candidate_adapter_sha256']
path=ROOT/'tests/cpu/cpu_store_credit/run.py'
text=path.read_text()
old="if not a.control:\n for f in (HERE/'rtl').rglob('*.sv'):\n  shutil.copyfile(f,source/'rtl'/f.relative_to(HERE/'rtl'))"
new="""for f in (ROOT/'tests/cpu/cpu_store_credit/rtl').rglob('*.sv'):
 shutil.copyfile(f,source/'rtl'/f.relative_to(ROOT/'tests/cpu/cpu_store_credit/rtl'))
if not a.control:
 for f in (HERE/'rtl').rglob('*.sv'):
  shutil.copyfile(f,source/'rtl'/f.relative_to(HERE/'rtl'))"""
# The reused wrapper installs its transformations before executing the 4A runner.
text=text.replace('assert text.count(old)==1', "new=new.replace("+repr(old)+","+repr(new)+")\nassert text.count(old)==1")
text=text.replace('build/sim/cpu-store-credit','build/sim/cpu-load-delivery').replace('tests/cpu/cpu_store_credit/observe.vh','tests/cpu/cpu_load_delivery/observe.vh')
exec(compile(text,str(Path(__file__)),'exec'),{'__file__':__file__,'__name__':'__main__'})
