#!/usr/bin/env python3
"""Reuse the focused real-CPU diagnostic campaign with this frozen variant."""
from pathlib import Path
import hashlib,json
from setup import ROOT

path=ROOT/'tests/cpu/cpu_store_postindex/diagnostics.py'
source=path.read_text().replace("ROOT/'build/sim/cpu-store-postindex'", "ROOT/'build/sim/cpu-load-pipeline'")
exec(compile(source,str(path),'exec'))
