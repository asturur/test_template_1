"""Exact published5A control and bounded owner-payload split."""
from pathlib import Path
import hashlib,json,shutil,types,subprocess
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
path=ROOT/'tests/cpu/cpu_frontend_delivery/setup.py';fixed=types.ModuleType('fixed5A');fixed.__file__=str(path)
exec(compile(path.read_text(),str(path),'exec'),fixed.__dict__)
evidence=json.loads((ROOT/'docs/evidence/cpu-frontend-delivery-20261117.json').read_text())
def overlay(destination,candidate=False):
 fixed.overlay(destination,True)
 for f in (destination/'rtl').rglob('*'):
  if f.is_file() and f.suffix in ['.sv','.v','.svh']:
   rel=str(f.relative_to(destination))
   expected=subprocess.check_output(['git','show','6ac7a9d:'+rel],cwd=ROOT)
   assert f.read_bytes()==expected,rel
 if candidate:
  for f in (HERE/'rtl').rglob('*.sv'):shutil.copyfile(f,destination/'rtl'/f.relative_to(HERE/'rtl'))
