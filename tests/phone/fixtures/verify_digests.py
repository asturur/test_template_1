#!/usr/bin/env python3
"""Verify stock descriptors against the selected, unmodified image inputs."""
import hashlib
import importlib.util
from pathlib import Path
import struct
ROOT = Path(__file__).resolve().parents[3]
core = ROOT / 'build/firmware/nem4-factory/core.bin'
extension = ROOT / 'build/firmware/nem4-factory/extension.bin'
linear = core.read_bytes() + extension.read_bytes()
start, end = struct.unpack_from('<II', linear, 0x8f00)
lo, hi = start - 0x50000000, end - 0x50000000 + 1
if not 0 <= lo < hi <= len(linear):
    raise SystemExit('extension descriptor is out of bounds')
actual = hashlib.md5(linear[lo:hi]).digest()
if actual != linear[0x8f08:0x8f18]:
    raise SystemExit('extension descriptor does not match selected inputs')
print('PASS extension digest', actual.hex(), flush=True)
path = ROOT / 'scratch/flash-cipher-r4/reproduce_stock_digest.py'
spec = importlib.util.spec_from_file_location('ngage_stock_digest', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.ROOT = ROOT
module.LINEAR = core
module.MODEL = ROOT / 'build/firmware/thc/scrambler-model.json'
raise SystemExit(module.main())
