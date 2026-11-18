#!/usr/bin/env python3
import hashlib,json,shutil
from pathlib import Path
from setup import ROOT
p=ROOT/'tests/cpu/cpu_store_postindex/diagnostics.py'
s=p.read_text().replace('from setup import *','').replace('cpu-store-postindex','cpu-load-admission')
exec(compile(s,str(p),'exec'))
