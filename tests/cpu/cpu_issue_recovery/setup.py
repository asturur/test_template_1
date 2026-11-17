"""Explicit final 4D control closure; only this experiment's overlay is mutable."""
from pathlib import Path
import hashlib,json,shutil,types
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
path=ROOT/'tests/cpu/cpu_load_overlap/setup.py'
fixed=types.ModuleType('fixed4D');fixed.__file__=str(path)
exec(compile(path.read_text(),str(path),'exec'),fixed.__dict__)
evidence=json.loads((ROOT/'docs/evidence/cpu-load-overlap-20261116.json').read_text())
assert evidence['candidate_source_id']=='76d176e29ae091962ebe66efe2cf0060f0d551f844fce29c014a5fd64fe6b4bb'
for f,h in evidence['overlay_sha256'].items():assert hashlib.sha256((ROOT/f).read_bytes()).hexdigest()==h,f
def overlay(destination,candidate=False,four_c=False):
 fixed.overlay(destination,not four_c)
 if candidate:
  for f in (HERE/'rtl').rglob('*.sv'):shutil.copyfile(f,destination/'rtl'/f.relative_to(HERE/'rtl'))
