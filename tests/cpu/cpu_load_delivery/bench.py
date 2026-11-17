#!/usr/bin/env python3
"""Original transpose with fixed 4B and one registered waiting-load probe policy."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
import hashlib,json
fixed=json.loads((ROOT/'docs/evidence/cpu-store-overlap-20261116.json').read_text())
assert fixed['candidate_source_id']=='dcbc85875b34ffaeafe289cea6ecd6e806ec37878fdbb5a8c85f7ded0c93edcb', '4A control identity changed'
for name,value in fixed['overlay_sha256'].items():
 assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==value,name
four_b=json.loads((ROOT/'docs/evidence/cpu-store-credit-20261116.json').read_text())
assert four_b['candidate_source_id']=='b104f42d3e661c9a8832e8d928babca8ac872dd67f76bdcfbfaa5f60626d6094'
assert hashlib.sha256((ROOT/'tests/cpu/cpu_store_credit/rtl/arm920/cache_adapter.sv').read_bytes()).hexdigest()==four_b['candidate_adapter_sha256']
path=ROOT/'tests/cpu/cpu_store_overlap/bench.py'
text=path.read_text()
old="  if not a.control:\n   for f in (HERE/'rtl').rglob('*'):\n    if f.is_file():shutil.copyfile(f,destination/'rtl'/f.relative_to(HERE/'rtl'))"
new="""  for f in (ROOT/'tests/cpu/cpu_store_overlap/rtl').rglob('*.sv'):
   shutil.copyfile(f,destination/'rtl'/f.relative_to(ROOT/'tests/cpu/cpu_store_overlap/rtl'))
  for f in (ROOT/'tests/cpu/cpu_store_credit/rtl').rglob('*.sv'):
   shutil.copyfile(f,destination/'rtl'/f.relative_to(ROOT/'tests/cpu/cpu_store_credit/rtl'))
  if not a.control:
   for f in (HERE/'rtl').rglob('*.sv'):
    shutil.copyfile(f,destination/'rtl'/f.relative_to(HERE/'rtl'))"""
assert text.count(old)==1
text=text.replace(old,new).replace('tests/cpu/cpu_store_overlap/payload_tb.v','tests/cpu/cpu_load_delivery/payload_tb.v')
exec(compile(text,str(Path(__file__)),'exec'),{'__file__':__file__,'__name__':'__main__'})
