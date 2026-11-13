#!/usr/bin/env python3
"""Inspect/apply the pinned no-radio BT experiment in volatile MiSTer DDR only.

Default is read-only. Apply requires a freshly loaded core kept in CPU Hold,
zero CPU history, restored images, autosave Off and two advancing DDR snapshots.
A warm CPU Hold after running is insufficient: D2/I-cache contents may be stale.
Original firmware files and C:/PMM are never written. Reload the RBF to undo.
"""
import argparse
import base64
import hashlib
import json
import mmap
import os
import struct
import sys
import time

BASE, SIZE, ROM_SIZE = 0x30000000, 0x1400000, 0x13F0000
ROM_SHA = '88fd596a23269ecb0d9f7544d540c59010d276574dbe3d0262c870c429e58329'
PACKAGE_SHA = '12b078de67083dffe006be7b0102444c9f2d0e6a3660674ff3cb2449de2ec2aa'
EXIT_TRACE_SHA = 'c76a4d881bb71dd5058dc7b1032d332aa0da61c2e098506edbde5764a09247d3'
VIEW_TIMEOUT_RECORDS = ((0x64bf68, 1000000, 10000000),
                        (0x64bf6c, 10000000, 100000000))
VIEW_CONFIG_RECORDS = ((0x63ea28, 0x1c01f8cb, 0x00c1f8cb),
                       (0x63ea3c, 0x68281c01, 0x682800c1))
EXIT_HOOKS = (0x3b4718, 0x3b46e0, 0x3b7fb8, 0x3b7fe4, 0x3b8010, 0x3a2b48, 0x3b247c)


def exit_records(blob, slow_wait=False):
    if hashlib.sha256(blob).hexdigest() != EXIT_TRACE_SHA:
        raise ValueError('requires the tested NEM-4 exit-trace payload')
    records = [(0x11b6000+i, 0xffffffff, struct.unpack_from('<I', blob, i)[0])
               for i in range(0, len(blob), 4)]
    for i, entry in enumerate(EXIT_HOOKS):
        if entry == 0x3b247c and not slow_wait:
            continue
        target = 0x11b6000 + i*4
        branch = 0xea000000 | (((target-entry-8)//4) & 0xffffff)
        old = (0xea003c0a if entry == 0x3a2b48 else
               0xe2844001 if entry == 0x3b247c else 0xe92d4000)
        records.append((entry, old, branch))
    return records


def records_from_package(data):
    if hashlib.sha256(data).hexdigest() != PACKAGE_SHA:
        raise ValueError('requires the audited Bluetooth_Compatibility.ngo package')
    return list(struct.iter_unpack('<III', data[64:]))


def snapshot(memory):
    valid = []
    for pos in (0x13FF000, 0x13FF400):
        before = bytes(memory[pos+1020:pos+1024])
        raw = bytes(memory[pos:pos+1024])
        after = bytes(memory[pos+1020:pos+1024])
        w = struct.unpack('<256I', raw)
        if (before == after == raw[-4:] and w[0:2] == (0x3244474E, 1)
                and w[255] != 0 and w[255] == (w[2] ^ 0x4344474E) and w[7] == 406):
            valid.append(w)
    if not valid:
        raise ValueError('no valid DDR diagnostic snapshot')
    newest = valid[0]
    if len(valid) == 2 and 0 < ((valid[1][2]-newest[2]) & 0xFFFFFFFF) < 0x80000000:
        newest = valid[1]
    return newest


def held_fresh(w):
    flags = w[242]
    # Monitor values: cycles4, fetches5, ACKs10, errors11, CPU flags22.
    return (all(w[8+i] == 0 for i in (4, 5, 10, 11)) and w[30] & 1
            and w[6] == 0 and (flags & 7) == 0 and flags & (1 << 4)
            and flags & (1 << 25) and not flags & ((1 << 6) | (1 << 7) | (1 << 10) | (1 << 26)))


def validate_image(memory, records):
    if hashlib.sha256(memory[:ROM_SIZE]).hexdigest() != ROM_SHA:
        raise ValueError('DDR ROM is not the exact original NEM-4 service image')
    for off, old, new in records:
        if struct.unpack_from('<I', memory, off)[0] != old:
            raise ValueError('original-word mismatch at0x%x' % off)


def patch_image(memory, records):
    # Install payload/allocation/checksum descriptor before publishing hook.
    hooks = set(EXIT_HOOKS) | {0x3f1cd0, 0x3f1cd4, 0x3f1cd8}
    ordered = [r for r in records if r[0] not in hooks]
    ordered += [r for r in records if r[0] in hooks]
    applied = []
    try:
        for off, old, new in ordered:
            struct.pack_into('<I', memory, off, new)
            applied.append((off, old, new))
        for off, old, new in records:
            if struct.unpack_from('<I', memory, off)[0] != new:
                raise ValueError('patched readback mismatch at0x%x' % off)
    except Exception:
        for off, old, new in reversed(applied):
            struct.pack_into('<I', memory, off, old)
        raise


def main():
    p = argparse.ArgumentParser(description=__doc__)
    source = p.add_mutually_exclusive_group(required=True)
    source.add_argument('--package')
    source.add_argument('--package-b64')
    p.add_argument('--apply', action='store_true')
    p.add_argument('--exit-trace-b64', help='also install the tested exit diagnostic payload')
    p.add_argument('--slow-wait-trace', action='store_true',
                   help='diagnostic only: trace slow file waits; adds runtime overhead')
    deadline = p.add_mutually_exclusive_group()
    deadline.add_argument('--view-config-scale8', action='store_true',
                          help='experiment: scale EikSrv configured2s/20s deadlines eightfold')
    deadline.add_argument('--view-timeout-scale10', action='store_true',
                   help='experiment: extend ViewSrv default soft/hard deadlines tenfold')
    args = p.parse_args()
    if args.slow_wait_trace and not args.exit_trace_b64:
        p.error('--slow-wait-trace requires --exit-trace-b64')
    if args.package:
        with open(args.package, 'rb') as f:
            package = f.read()
    else:
        package = base64.b64decode(args.package_b64, validate=True)
    records = records_from_package(package)
    if args.exit_trace_b64:
        records += exit_records(base64.b64decode(args.exit_trace_b64, validate=True), args.slow_wait_trace)
    if args.view_timeout_scale10:
        records += list(VIEW_TIMEOUT_RECORDS)
    if args.view_config_scale8:
        records += list(VIEW_CONFIG_RECORDS)
    records.sort()
    flags = (os.O_RDWR if args.apply else os.O_RDONLY) | os.O_SYNC
    fd = os.open('/dev/mem', flags)
    try:
        with mmap.mmap(fd, SIZE, access=mmap.ACCESS_WRITE if args.apply else mmap.ACCESS_READ,
                       offset=BASE) as memory:
            first = snapshot(memory)
            validate_image(memory, records)
            report = dict(mode='apply' if args.apply else 'read-only preflight', records=len(records),
                          package_sha256=PACKAGE_SHA, original_rom_sha256=ROM_SHA,
                          exit_trace_sha256=EXIT_TRACE_SHA if args.exit_trace_b64 else None,
                          slow_wait_trace=args.slow_wait_trace,
                          view_timeout_scale=10 if args.view_timeout_scale10 else 1,
                          view_config_scale=8 if args.view_config_scale8 else 1,
                          fresh_held=bool(held_fresh(first)), applied=False,
                          requires='fresh RBF load in CPU Hold, no prior execution, autosave Off')
            if args.apply:
                if not held_fresh(first):
                    raise ValueError('REFUSED: core has run or is not freshly held; no writes made')
                deadline = time.monotonic() + 3
                while True:
                    time.sleep(0.1)
                    second = snapshot(memory)
                    if not held_fresh(second):
                        raise ValueError('REFUSED: CPU Hold/freshness changed; no writes made')
                    if second[2] != first[2]:
                        break
                    if time.monotonic() >= deadline:
                        raise ValueError('REFUSED: telemetry is not advancing; no writes made')
                patch_image(memory, records)
                report.update(applied=True, patched_rom_sha256=hashlib.sha256(memory[:ROM_SIZE]).hexdigest(),
                              rollback='reload the RBF; original service/disk files unchanged')
            print(json.dumps(report, indent=2))
    finally:
        os.close(fd)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(2)
