#!/usr/bin/env python3
"""Scan a board checkpoint's SDRAM for the 176x208 0x0RGB framebuffer and
render candidates to PNG. The N-Gage panel is 16bpp 0x0RGB (top nibble 0,
per ~/develop/n-gage/docs/hardware.md), so a real frame has every high
byte's top nibble clear across the whole 71.5 KiB buffer.

Usage: scan_framebuffer.py <checkpoint.host> <out_dir>
(made with Claude, 2026-10-30)
"""
import struct, sys, zlib, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import inspect_checkpoint as IC
from pathlib import Path

W, H = 176, 208
FRAME = W * H * 2

ram = IC.load_sdram(Path(sys.argv[1]))
out = sys.argv[2]
os.makedirs(out, exist_ok=True)


def render(buf, path):
    rows = []
    for r in range(H):
        row = b'\0'
        for c in range(W):
            i = (r * W + c) * 2
            v = buf[i] | buf[i + 1] << 8
            row += bytes((((v >> 8) & 0xf) * 17, ((v >> 4) & 0xf) * 17, (v & 0xf) * 17))
        rows.append(row)
    raw = b''.join(rows)

    def chunk(k, c):
        return struct.pack('>I', len(c)) + k + c + struct.pack('>I', zlib.crc32(k + c) & 0xffffffff)
    png = (b'\x89PNG\r\n\x1a\n' +
           chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0)) +
           chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))
    open(path, 'wb').write(png)


hits = []
for base in range(0, len(ram) - FRAME, 0x100):
    if any(ram[base + 1 + i] & 0xf0 for i in range(0, FRAME, 2)):
        continue                                   # a non-0x0RGB halfword rules it out
    nz = sum(1 for i in range(0, FRAME, 2) if ram[base + i] or ram[base + i + 1])
    frac = nz / (FRAME // 2)
    if frac < 0.02:                                # all-black: not a drawn frame
        continue
    pa = 0x0a000000 + base
    hits.append((pa, frac))
    render(ram[base:base + FRAME], os.path.join(out, 'fb_%08x.png' % pa))
    print('framebuffer candidate PA %#010x nonzero=%.2f' % (pa, frac))

print('%d candidate(s)' % len(hits))
