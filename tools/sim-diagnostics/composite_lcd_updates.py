#!/usr/bin/env python3
"""Composite a run's LCD DMA updates into screen states.

Each wserv update is a full-width line band: y = (DMA src - 0x0a000020)/352,
length = count words / 88 lines (header low16 = 3*words-1 is only a length).
Pairs the 0x348=2 arms in bus.tsv (src from the preceding 0x354 write) with
the word streams in lcd-dma.tsv, applies them in order, and writes a PNG of
the screen after every update (or --last for just the final state).

Usage: composite_lcd_updates.py <run_dir> <out_dir> [--last]
(made with Claude, 2026-10-31)
"""
import csv, struct, sys, zlib, os

W, H = 176, 208
FB = 0x0a000020


def px(v):
    return bytes((((v >> 8) & 0xf) * 17, ((v >> 4) & 0xf) * 17, (v & 0xf) * 17))


def png(rgb, path):
    raw = b''.join(b'\0' + rgb[r * W * 3:(r + 1) * W * 3] for r in range(H))

    def ch(k, c):
        return struct.pack('>I', len(c)) + k + c + struct.pack('>I', zlib.crc32(k + c) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' +
                           ch(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0)) +
                           ch(b'IDAT', zlib.compress(raw, 9)) + ch(b'IEND', b''))


def main():
    run, out = sys.argv[1], sys.argv[2]
    last_only = '--last' in sys.argv
    os.makedirs(out, exist_ok=True)
    arms = []
    src = 0
    for row in csv.DictReader(open(os.path.join(run, 'bus.tsv')), delimiter='\t'):
        if row['operation'] != 'WRITE':
            continue
        if row['address'] == '0x0c120354':
            src = int(row['data'], 16)
        elif row['address'] == '0x0c120348' and int(row['data'], 16) == 2:
            arms.append(((src - FB) // 352, int(row['cycle'])))
    frames, cur = [], None
    for row in csv.DictReader(open(os.path.join(run, 'lcd-dma.tsv')), delimiter='\t'):
        if row['address'] == '0x0c121200':
            cur = []
            frames.append(cur)
        elif cur is not None:
            cur.append(int(row['data'], 16))
    # a resume-served transfer (pre-v6 checkpoint) has a frame but no arm row
    if len(frames) == len(arms) + 1:
        arms.insert(0, (0, 0))
    print('%d arms, %d frames' % (len(arms), len(frames)))
    screen = bytearray(W * H * 3)
    for i, ((y, cyc), words) in enumerate(zip(arms, frames)):
        buf = bytearray()
        for w in words:
            buf += px(w & 0xffff) + px((w >> 16) & 0xffff)
        end = min(len(buf), W * H * 3 - y * W * 3)
        screen[y * W * 3:y * W * 3 + end] = buf[:end]
        if not last_only:
            png(bytes(screen), os.path.join(out, 'state%03d_c%d.png' % (i, cyc)))
    png(bytes(screen), os.path.join(out, 'final.png'))
    print('wrote %s/final.png%s' % (out, '' if last_only else ' and per-update states'))


if __name__ == '__main__':
    main()
