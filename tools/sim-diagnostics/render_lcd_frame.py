#!/usr/bin/env python3
"""Render the firmware-drawn LCD frame(s) from a bus trace to PNG.

Unlike sim/capture_lcd_screen.py (which only recognises the uniform white
clear), this renders ANY 176x208 frame the firmware sends, so the Nokia /
N-Gage splash can be seen. The LCD transport: header writes to 0x0c121200,
pixel data to 0x0c121208. A full frame is ~18304 32-bit words = 36608
16-bit pixels = 176x208. Pixel format is 0x0RGB-ish (RGB444 in the low
12 bits; the clear uses 0xffff = white). Both halfword orderings are tried
and saved so the correct one is obvious.

Usage: render_lcd_frame.py <bus.tsv> <out_dir>
(made with Claude, 2026-10-30)
"""
import csv
import struct
import sys
import zlib
import os

W, H = 176, 208
PIX = W * H                      # 36608
WORDS = PIX // 2                 # 18304


def png(pixels_rgb, path):
    raw = b''.join(b'\0' + pixels_rgb[r * W * 3:(r + 1) * W * 3] for r in range(H))

    def chunk(k, c):
        return struct.pack('>I', len(c)) + k + c + struct.pack('>I', zlib.crc32(k + c) & 0xffffffff)
    data = (b'\x89PNG\r\n\x1a\n' +
            chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))
    open(path, 'wb').write(data)


def px444(v):
    # 0x0RGB (RGB444) in the low 12 bits
    return bytes((((v >> 8) & 0xf) * 17, ((v >> 4) & 0xf) * 17, (v & 0xf) * 17))


def render(words, path_stem):
    # two pixels per 32-bit word; try low-first and high-first halfword order
    for order, name in (((0, 16), 'lohi'), ((16, 0), 'hilo')):
        buf = bytearray()
        for w in words:
            buf += px444((w >> order[0]) & 0xffff)
            buf += px444((w >> order[1]) & 0xffff)
        if len(buf) < PIX * 3:
            buf += b'\0' * (PIX * 3 - len(buf))
        png(bytes(buf[:PIX * 3]), '%s-%s.png' % (path_stem, name))


def main():
    bus, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    transfers = []
    cur = None
    with open(bus, newline='') as f:
        for row in csv.DictReader(f, delimiter='\t'):
            if row.get('device') != 'lcd_probe_transport' or row.get('operation') != 'WRITE':
                continue
            addr, data, cyc = int(row['address'], 16), int(row['data'], 16), int(row['cycle'])
            if addr == 0x0c121200:
                cur = dict(cycle=cyc, header=data, words=[])
                transfers.append(cur)
            elif addr == 0x0c121208 and cur is not None:
                cur['words'].append(data)
    frames = [t for t in transfers if len(t['words']) >= WORDS // 2]
    if not frames:
        print('no frame-sized transfers (largest = %d words)' %
              max((len(t['words']) for t in transfers), default=0))
        return
    for i, t in enumerate(frames):
        stem = os.path.join(out, 'frame%02d_c%d_%06x' % (i, t['cycle'], t['header'] & 0xffffff))
        render(t['words'][:WORDS], stem)
        uniq = len(set(t['words']))
        print('frame %d: cycle %d header %#x words %d unique %d -> %s-{lohi,hilo}.png' %
              (i, t['cycle'], t['header'], len(t['words']), uniq, stem))


if __name__ == '__main__':
    main()
