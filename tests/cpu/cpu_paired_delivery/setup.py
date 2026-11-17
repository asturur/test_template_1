"""Pinned accepted5C control, with one selectable isolated paired-result overlay."""
from pathlib import Path
import subprocess,shutil,hashlib,json
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
BASE='78d53d4c129e761d979794c38398aa72ecf87f87'
def overlay(destination,candidate=False):
 # The common memory fixture initially freezes its historical base. Replace
 # the explicit project-only source closure with accepted5C, without checkout.
 import sys
 sys.path.insert(0,str(ROOT/'tests/cpu/donor_import'))
 import importlib.util
 spec=importlib.util.spec_from_file_location('paired_freezer',ROOT/'tests/cpu/donor_import/run.py');support=importlib.util.module_from_spec(spec);spec.loader.exec_module(support)
 names=subprocess.check_output(['git','ls-tree','-r','--name-only',BASE],cwd=ROOT,text=True).splitlines()
 for name in names:
  if support.source_path(name):
   p=destination/name;p.parent.mkdir(parents=True,exist_ok=True)
   p.write_bytes(subprocess.check_output(['git','show',BASE+':'+name],cwd=ROOT))
 if candidate:
  for f in (HERE/'rtl').rglob('*.sv'):shutil.copyfile(f,destination/'rtl'/f.relative_to(HERE/'rtl'))
