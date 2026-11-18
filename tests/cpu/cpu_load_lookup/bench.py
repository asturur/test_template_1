#!/usr/bin/env python3
"""Run unchanged checked 5J workloads on 5F, P1, or P1 plus earlier private lookup."""
import argparse,sys
from pathlib import Path
import setup
from setup import ROOT,HERE

p=argparse.ArgumentParser(add_help=False)
p.add_argument('--variant',choices=['5f','p1','lookup'],default='lookup')
a,rest=p.parse_known_args();setup.MODE=a.variant
path=ROOT/'tests/cpu/cpu_load_pipeline/bench.py'
source=path.read_text().replace("ROOT/'build/sim/cpu-load-pipeline'", "ROOT/'build/sim/cpu-load-lookup'")
source=source.replace("'5J-control' if a.control else '5J-P1-load'", repr('5K-'+a.variant))
source=source.replace("'control' if a.control else 'candidate'",repr(a.variant))
source=source.replace("['span','transpose','stream','dependency']", "['span','transpose','stream','dependency','multiline']")
source=source.replace("['stream','dependency']", "['stream','dependency','multiline']")
source=source.replace("kind=='stream'", "kind in ['stream','multiline']")
source=source.replace("{4*i}", "{(32 if kind=='multiline' else 4)*i}")
source=source.replace("sp.words([0x100+i for i in range(32)])", "sp.words([0x100+i for i in range(64 if kind=='multiline' else 32)])")
source=source.replace("kind=='dependency'", "kind in ['dependency','multiline']")
source=source.replace("c['id']=='stream'", "c['id'] in ['stream','multiline']")
source=source.replace("script_sha256=sha(Path(__file__)))",
    "script_sha256=sha(Path(__file__)),driver_inputs={str(f.relative_to(ROOT)):sha(f) for f in [ROOT/'tests/cpu/cpu_load_pipeline/bench.py',HERE/'setup.py',HERE/'observe.vh']})")
if a.variant=='lookup':
    source=source.replace("'-DNGAGE_RUNTIME_TRACE','-DBENCH_HAS_LINE',", "'-DNGAGE_RUNTIME_TRACE','-DBENCH_HAS_LINE','-DLOOKUP_PROBE',")
sys.argv=[str(path),*(['--control'] if a.variant=='5f' else []),*rest]
exec(compile(source,str(path),'exec'))
