"""Fixed qualified5B owner split plus one zero-addend multiply experiment."""
from pathlib import Path
import hashlib,json,shutil,types
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
path=ROOT/'tests/cpu/cpu_owner_split/setup.py';fixed=types.ModuleType('fixed5B');fixed.__file__=str(path)
exec(compile(path.read_text(),str(path),'exec'),fixed.__dict__)
evidence=json.loads((ROOT/'docs/evidence/cpu-owner-split-20261117.json').read_text())
def overlay(destination,candidate=False):
 fixed.overlay(destination,True)
 if candidate:
  for f in (HERE/'rtl').rglob('*.sv'):shutil.copyfile(f,destination/'rtl'/f.relative_to(HERE/'rtl'))
