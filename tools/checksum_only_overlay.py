#!/usr/bin/env python3
"""Derive bounded diagnostic subsets of the NOS compatibility package."""
import argparse
from pathlib import Path
import struct
import zlib

import nos_overlay


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path)
    parser.add_argument('--variant', choices=('checksum-only','bootstrap-only','driver-only'), default='checksum-only')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    names = {'checksum-only':'TEST_Checksum_Only.ngo',
             'bootstrap-only':'TEST_NOS_Bootstrap_Only.ngo',
             'driver-only':'TEST_NOS_Driver_Only.ngo'}
    if args.input is None:
        args.input = Path('runtime/overlays') / ('TEST_NOS_Full_Experimental.ngo' if args.variant == 'bootstrap-only' else 'NOS_Compatibility.ngo')
    if args.output is None:
        args.output = Path('runtime/overlays') / names[args.variant]
    if args.input.resolve() == args.output.resolve():
        parser.error('diagnostic output must not replace the full NOS package')
    source = args.input.read_bytes()
    original_records = {a: (old, new) for a, old, new in nos_overlay.inspect(source)}
    records = [(0x8f18, 0x50009000, 0xffffffff),
               (0x8f1c, 0x511b4fff, 0xffffffff)]
    for address, old, new in records:
        if original_records.get(address) != (old, new):
            raise ValueError('missing audited checksum descriptor undo values')
    if args.variant != 'checksum-only':
        for address, (old, new) in sorted(original_records.items()):
            bootstrap = 0x320860 <= address < 0x320980 or address == 0x350504
            driver = address in (0x11b4028,0x11b4030,0x11b413c) or 0x11b6000 <= address < 0x11c0000
            if (args.variant == 'bootstrap-only' and bootstrap) or (args.variant == 'driver-only' and driver):
                records.append((address, old, new))
        if len(records) == 2:
            raise ValueError('input is missing the requested NOS component')
    records.sort()
    body = b''.join(struct.pack('<III', *record) for record in records)
    header = list(struct.unpack('<16I', source[:64]))
    header[3] = len(records)
    header[4] = zlib.crc32(body)
    header[11] = 64 + len(body)
    first = struct.pack('<15I', *header[:15])
    package = first + struct.pack('<I', zlib.crc32(first)) + body
    assert nos_overlay.inspect(package) == records
    if args.variant == 'checksum-only':
        assert len(package) == 88
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(package)
    print(f'Created {args.output}: {args.variant}, {len(records)} records; no BT, C: or UI changes')


if __name__ == '__main__':
    main()
