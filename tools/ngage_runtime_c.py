#!/usr/bin/env python3
"""Capture a stable raw C: image directly from MiSTer DDR, without a save.

Over SSH: ssh root@MISTER 'python3 -' < tools/ngage_runtime_c.py > live-c.vhd
Checks consecutive equal reads; never pauses the CPU or writes physical memory.
This captures committed flash backing, not uncommitted guest file-server RAM.
"""
import argparse
import hashlib
import json
import mmap
import os
import sys
import time

BASE, SIZE = 0x31400000, 4194304


def stable_copy(memory, attempts):
    previous = bytes(memory[:SIZE])
    for attempt in range(attempts):
        current = bytes(memory[:SIZE])
        if current == previous:
            return current, attempt + 2
        previous = current
        time.sleep(0.1)
    raise ValueError('C: changed between reads; no stable capture emitted, try again later')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--attempts', type=int, default=3)
    p.add_argument('--output', default='-', help='new output file or - for binary stdout')
    args = p.parse_args()
    if not 1 <= args.attempts <= 20:
        p.error('attempts must be1..20')
    fd = os.open('/dev/mem', os.O_RDONLY | os.O_SYNC)
    try:
        with mmap.mmap(fd, SIZE, access=mmap.ACCESS_READ, offset=BASE) as memory:
            raw, reads = stable_copy(memory, args.attempts)
    finally:
        os.close(fd)
    if args.output == '-':
        sys.stdout.buffer.write(raw)
        sys.stdout.buffer.flush()
    else:
        with open(args.output, 'xb') as out:
            out.write(raw)
    print(json.dumps(dict(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                          consecutive_equal_reads=2, reads=reads, physical_base=hex(BASE))), file=sys.stderr)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(2)
