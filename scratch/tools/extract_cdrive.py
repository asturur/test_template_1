#!/usr/bin/env python3
"""Extract the C: flash overlay (4 MiB LFFS volume) from a board checkpoint.

The board .host blob stores the overlay as a u64 size marker (0x400000)
followed by the raw volume; the right candidate is the one whose 64 KiB
blocks carry the LFFS magic 0x503b3b60 at block offset +4.

Usage: extract_cdrive.py <checkpoint.host> <out.img>
(made with Claude, 2026-10-30)
"""
import struct, sys

blob = open(sys.argv[1], 'rb').read()
marker = struct.pack('<Q', 0x400000)
best = None
pos = -1
while True:
    pos = blob.find(marker, pos + 1)
    if pos < 0:
        break
    if pos + 8 + 0x400000 > len(blob):
        continue
    img = blob[pos + 8:pos + 8 + 0x400000]
    magics = sum(1 for b in range(0, 0x400000, 0x10000)
                 if struct.unpack_from('<I', img, b + 4)[0] == 0x503b3b60)
    if best is None or magics > best[1]:
        best = (pos, magics)
if not best or best[1] == 0:
    raise SystemExit('no LFFS volume found in the blob')
pos, magics = best
open(sys.argv[2], 'wb').write(blob[pos + 8:pos + 8 + 0x400000])
print('extracted from %#x: %d/64 blocks carry the LFFS magic' % (pos, magics))
