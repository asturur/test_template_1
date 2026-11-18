"""Pinned post-Quartus-width-fix5F control; optional single5G overlay."""
from pathlib import Path
import subprocess,shutil,hashlib,json
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
BASE='8e70b1ebc16486443d09f008384b4c0bc41c071c'
def overlay(destination,candidate=False):
 if candidate:
  for f in (HERE/'rtl').rglob('*.sv'):
   shutil.copyfile(f,destination/'rtl'/f.relative_to(HERE/'rtl'))
