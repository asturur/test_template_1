"""Exact passing 4G control and one bounded frontend delivery experiment."""
from pathlib import Path
import hashlib,json,shutil,types
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
path=ROOT/'tests/cpu/cpu_store_second/setup.py';fixed=types.ModuleType('fixed4G');fixed.__file__=str(path)
exec(compile(path.read_text(),str(path),'exec'),fixed.__dict__)
evidence=json.loads((ROOT/'docs/evidence/cpu-store-second-20261116.json').read_text())
assert evidence['candidate_source_id']=='7b9a7dd28baccdfedfe75baaac91358c7751ed56d977fe348101738946e40244'
for f,h in evidence['overlay_sha256'].items():assert hashlib.sha256((ROOT/f).read_bytes()).hexdigest()==h,f
def overlay(destination,candidate=False):
 fixed.overlay(destination,True)
 if candidate:
  for f in (HERE/'rtl').rglob('*.sv'):shutil.copyfile(f,destination/'rtl'/f.relative_to(HERE/'rtl'))
