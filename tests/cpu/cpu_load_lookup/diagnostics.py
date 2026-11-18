#!/usr/bin/env python3
"""Focused actual CPU diagnostics on the frozen earlier-lookup CPU."""
import hashlib,json
from setup import ROOT
path=ROOT/'tests/cpu/cpu_store_postindex/diagnostics.py'
source=path.read_text().replace("ROOT/'build/sim/cpu-store-postindex'", "ROOT/'build/sim/cpu-load-lookup'")
exec(compile(source,str(path),'exec'))
