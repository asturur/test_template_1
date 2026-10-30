#!/usr/bin/env python3
"""Dump the live cbus.dll UEM-interrupt client arrays from a board checkpoint.

cbus ISR (0x50382498, src 0x76): obj=[handler+0x14]; reads UIF 0x150100 bit
0x8000, acks, reads UEM reg (1,0x15) and (1,0x05) via serial engine, then
dispatches {mask,TCallback*} arrays at obj+0xa4 (16) and obj+0x124 (8);
third ISR path (0x503824f8) checks 0x150102 bit 0x10 -> callback at +0x164.
(made with Claude, 2026-10-30)
"""
import struct, sys
sys.path.insert(0, 'scratch/tools')
import inspect_checkpoint as IC
from pathlib import Path

ram = IC.load_sdram(Path(sys.argv[1]))
IC._RAM = ram
IC.L1_BASE = IC.find_l1(ram)

def rd(va):
    off = IC.va_off(va)
    if off is None: return None
    return struct.unpack_from('<I', ram, off)[0]

# find handler objects whose vtable's slot +8 is an ISR in cbus.dll (0x50381d30-0x50383e80)
CBUS_LO, CBUS_HI = 0x50381d30, 0x50383e80
hits = []
for mb in range(16):
    for pg in range(0, 0x100000, 0x1000):
        va = 0x80000000 + mb*0x100000 + pg
        off = IC.va_off(va)
        if off is None: continue
        for i in range(0, 0x1000, 4):
            v = struct.unpack_from('<I', ram, off+i)[0]
            # candidate vtable pointer: points into ROM, and [v+8] is a cbus ISR
            if 0x50000000 <= v < 0x51400000:
                t = rd(v+8)
                if t is not None and CBUS_LO <= t < CBUS_HI and (t & 3)==0:
                    hits.append((va+i, v, t))
print("handler-vtable candidates ([obj+0x10]->vt with vt[2] in cbus):")
seen = set()
for addr, vt, isr in hits:
    if isr in (0x50382498, 0x503824c8, 0x503824f8):
        obj = addr - 0x10
        if obj in seen: continue
        seen.add(obj)
        en = rd(obj+4); target = rd(obj+0x14)
        print("  handler obj %08x enabled=%s isr=%08x cbusobj=%08x" % (obj, en, isr, target))
        if isr == 0x50382498 and target:
            base = target
            print("  == cbus object %08x ==" % base)
            print("  vtable:", hex(rd(base) or 0))
            for nm, o, n in (("reg0x35-clients", 0xa4, 16), ("reg0x05-clients", 0x124, 8)):
                print("  %s @+%#x:" % (nm, o))
                for k in range(n):
                    m = rd(base+o+8*k); cb = rd(base+o+8*k+4)
                    if m or cb:
                        fn = rd(cb) if cb else None
                        arg = rd(cb+4) if cb else None
                        print("    [%2d] mask=%08x cb=%08x fn=%s arg=%s" % (k, m or 0, cb or 0,
                              hex(fn) if fn is not None else '-', hex(arg) if arg is not None else '-'))
            cb = rd(base+0x164)
            print("  third-isr cb @+0x164: %s" % hex(cb or 0))
            if cb:
                print("    fn=%s arg=%s" % (hex(rd(cb) or 0), hex(rd(cb+4) or 0)))
