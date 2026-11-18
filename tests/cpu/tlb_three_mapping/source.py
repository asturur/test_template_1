"""Freeze the published 5L control and apply only the checked D-slot patch."""
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BASE = '0c380ab9bae92916d297b72d6a303d251f1d49d9'
IMAGE = 'jotego/simulator:arm64'
CHANGED = {'rtl/arm920/tlb.sv', 'rtl/arm/zap_dcache.sv'}


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


sys.path.insert(0, str(ROOT/'tests/cpu/donor_import'))
try:
    support = load('five_l_source_support', ROOT/'tests/cpu/donor_import/run.py')
finally:
    sys.path.pop(0)


def overlay(destination, candidate):
    if candidate:
        subprocess.run(['patch', '-s', '-p1', '-i', str(HERE/'third-mapping.patch')],
                       cwd=destination, check=True)


def freeze(destination, candidate):
    control = support.snapshot(destination, BASE)
    prior = json.loads((ROOT/'docs/evidence/tlb-area-20261117.json').read_text())
    expected = prior['control_manifest']['source']['files']
    cpu = {name for name in control['files'] if name.startswith('rtl/')
           and Path(name).suffix in {'.v', '.sv', '.vh', '.svh'}}
    assert len(cpu) == 60
    assert all(control['files'][name] == expected[name] for name in cpu)
    overlay(destination, candidate)
    frozen = support.source_manifest(destination, BASE, '5L + third D mapping' if candidate else 'exact 5L')
    assert frozen['files'].keys() == control['files'].keys()
    changed = {name for name, sha in frozen['files'].items() if sha != control['files'][name]}
    assert changed == (CHANGED if candidate else set())
    return frozen


def compiler_sources(source):
    files = [source/'rtl/ngage_cpu.sv', source/'rtl/ngage_bram.v']
    for directory in ('arm', 'arm920'):
        files.extend(sorted(path for path in (source/'rtl'/directory).iterdir()
                            if path.suffix in ('.v', '.sv')))
    return files
