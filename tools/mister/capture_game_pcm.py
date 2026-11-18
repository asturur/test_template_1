#!/usr/bin/env python3
"""Capture a short 48 kHz WAV from the MiSTer core's DDR audio monitor."""
import argparse
import hashlib
import json
import mmap
import os
from pathlib import Path
import struct
import time
import wave

BASE = 0x31900000
RING = 0x40000
FRAMES = 65536
RATE = 48000
DROP_MASK = 0x3fffffff


def read_ring(memory, length):
    before = struct.unpack_from('<I', memory, 0)[0]
    time.sleep(0.03)
    end, status = struct.unpack_from('<II', memory, 0)
    if end <= before or end < length or end & 255:
        raise ValueError('PCM monitor is inactive, reset or warming up')
    start = (end - length) % FRAMES
    first = min(length, FRAMES - start)
    data = memory[RING + start*4:RING + (start+first)*4]
    if first < length:
        data += memory[RING:RING + (length-first)*4]
    last, final_status = struct.unpack_from('<II', memory, 0)
    if last < end or last - end + length + 256 >= FRAMES:
        raise ValueError('PCM ring changed faster than it could be copied')
    if (status | final_status) & DROP_MASK:
        raise ValueError('PCM monitor dropped frames during this core session')
    return data, end, status


def capture(output, length):
    fd = os.open('/dev/mem', os.O_RDONLY | os.O_SYNC)
    try:
        with mmap.mmap(fd, RING + FRAMES*4, access=mmap.ACCESS_READ,
                       offset=BASE) as memory:
            data, end, activity = read_ring(memory, length)
    finally:
        os.close(fd)
    with wave.open(str(output), 'wb') as wav:
        wav.setparams((2, 2, RATE, 0, 'NONE', 'not compressed'))
        wav.writeframes(data)
    channels = list(struct.iter_unpack('<hh', data))
    report = dict(
        sample_end=end, frames=len(channels),
        nonzero_frames=sum(bool(left or right) for left, right in channels),
        min_left=min(left for left, _ in channels),
        max_left=max(left for left, _ in channels),
        min_right=min(right for _, right in channels),
        max_right=max(right for _, right in channels),
        nonzero_pcm_overlapped_mmc=bool(activity & (1 << 30)),
        nonzero_pcm_overlapped_lcd_dma=bool(activity & (1 << 31)),
        sha256=hashlib.sha256(output.read_bytes()).hexdigest(),
    )
    print(json.dumps(report))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--frames', type=int, default=RATE)
    args = parser.parse_args()
    if not 1 <= args.frames <= RATE:
        parser.error('--frames must be between 1 and 48000')
    capture(args.output, args.frames)
