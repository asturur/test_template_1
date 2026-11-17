"""Exact corrected 4E control; isolated early-store-address/late-data overlay."""
from pathlib import Path
import hashlib,json,shutil,types
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
path=ROOT/'tests/cpu/cpu_issue_recovery/setup.py';fixed=types.ModuleType('fixed4E');fixed.__file__=str(path)
exec(compile(path.read_text(),str(path),'exec'),fixed.__dict__)
evidence=json.loads((ROOT/'docs/evidence/cpu-issue-recovery-20261116.json').read_text())
assert evidence['candidate_source_id']=='9c2f022a85f3dad30026752e4537debca035b26a832821bcef950caf6edfab1c'
for f,h in evidence['overlay_sha256'].items():assert hashlib.sha256((ROOT/f).read_bytes()).hexdigest()==h,f
def overlay(destination,candidate=False):
 fixed.overlay(destination,True)
 if candidate:
  for f in (HERE/'rtl').rglob('*.sv'):shutil.copyfile(f,destination/'rtl'/f.relative_to(HERE/'rtl'))
