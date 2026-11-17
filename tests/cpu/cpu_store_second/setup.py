"""Exact passing 4F control and bounded 4G second-store data ownership."""
from pathlib import Path
import hashlib,json,shutil,types
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
path=ROOT/'tests/cpu/cpu_store_late/setup.py';fixed=types.ModuleType('fixed4F');fixed.__file__=str(path)
exec(compile(path.read_text(),str(path),'exec'),fixed.__dict__)
evidence=json.loads((ROOT/'docs/evidence/cpu-store-late-20261116.json').read_text())
assert evidence['candidate_source_id']=='0bf6550b3c7d9035f3d7c548c4731076b88ed024ed8590f1ebef0df320f1f081'
for f,h in evidence['overlay_sha256'].items():assert hashlib.sha256((ROOT/f).read_bytes()).hexdigest()==h,f
def overlay(destination,candidate=False):
 fixed.overlay(destination,True)
 if candidate:
  for f in (HERE/'rtl').rglob('*.sv'):shutil.copyfile(f,destination/'rtl'/f.relative_to(HERE/'rtl'))
