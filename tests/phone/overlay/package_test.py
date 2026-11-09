#!/usr/bin/env python3
"""Audit built private packages against the approved NOS/BT-only patch scope."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
import nos_overlay

nos = nos_overlay.inspect(Path(sys.argv[1]).read_bytes())
bt_bytes = Path(sys.argv[2]).read_bytes()
bt = nos_overlay.inspect(bt_bytes, overlay_id=2)
try:
    nos_overlay.inspect(bt_bytes)
except ValueError:
    pass
else:
    raise AssertionError('Bluetooth pack accepted as NOS')
n = {a: (old, new) for a, old, new in nos}
b = {a: (old, new) for a, old, new in bt}
assert n.keys() & b.keys() == {0x8f18, 0x8f1c}
assert all(n[a] == b[a] for a in n.keys() & b.keys())
# Hardware establishes that the fake NOS bootstrap prevents the logo. The
# production pack must retain original nosstarter/service-table initialization.
for address in n:
    assert (address in (0x8f18, 0x8f1c, 0x11b4028, 0x11b4030, 0x11b413c)
            or 0x11b6000 <= address < 0x11c0000), hex(address)
# The only sanctioned changes are two checksum descriptor words, BTLDD's
# three-word write tail, object allocation size and the erased injected tail.
for address in b:
    assert (address in (0x8f18, 0x8f1c, 0x3f28b0)
            or 0x3f1cd0 <= address < 0x3f1cdc
            or 0x11b4600 <= address < 0x11b6000), hex(address)
print('PASS independent package types; only shared checksum overlap; no C:/PMM/UI/startup patches')
