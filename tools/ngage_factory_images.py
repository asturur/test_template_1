#!/usr/bin/env python3
"""Create factory-state C: and PMM images for a first boot. Never overwrites.

C: is 4 MiB of erased flash. The PMM is 64 KiB of erased flash with the four
sector headers the stock firmware writes when it formats an erased PMM, and
one record: AUX startup reason (group 212, record 3) = 105.

The stock firmware does not mount an erased C:. EStart then asks HelperDrv
for the AUX startup reason, which NOS reads from that PMM record (100 when
the record is missing), and formats C: only when the answer is 105. The
firmware replaces the record with 100 after the format. See
docs/factory-first-boot.md.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

C_SIZE = 4194304
PMM_SIZE = 65536
SECTOR = 16384
# The first 32 bytes of each PMM sector after the stock 4.03 firmware has
# formatted an erased PMM: two catalogue sectors and two spare sectors.
CATALOGUE_A = bytes.fromhex('f0f0f8ff0200504d4d4341540100000000000000ffffffff0200ffffffffffff')
CATALOGUE_B = bytes.fromhex('f0f0f8ff0200504d4d4341540100000000000200ffffffff0200ffffffffffff')
SPARE = bytes.fromhex('f0f0feffffffffffffffffff01000000ffffffffffffffffffffffffffffffff')
AUX_STARTUP_REASON = (212, 3)
FORMAT_USER_AREA = 105
NORMAL = 100


def record(group, number, payload, offset):
    """A valid PMM record as the firmware writes it, placed at offset."""
    if not (0 <= group <= 255 and 0 <= number <= 0xffff and len(payload) <= 0xffff):
        raise ValueError('record does not fit the PMM record header')
    following = offset + 12 + len(payload)
    if following > SECTOR - 12:
        raise ValueError('record does not fit the sector')
    return (bytes((0xf4, group)) + struct.pack('<H', number) + b'\x55\xff\xff\xff' +
            struct.pack('<HH', len(payload), following) + payload)


def factory_pmm(reason=FORMAT_USER_AREA):
    image = bytearray(b'\xff' * PMM_SIZE)
    for index, header in enumerate((CATALOGUE_A, SPARE, CATALOGUE_B, SPARE)):
        image[index * SECTOR:index * SECTOR + len(header)] = header
    entry = record(*AUX_STARTUP_REASON, struct.pack('<H', reason), 32)
    image[32:32 + len(entry)] = entry
    return bytes(image)


def records(image, sector=0):
    """(offset, tag, group, number, payload) of each record in a catalogue sector."""
    base = sector * SECTOR
    offset = 32
    found = []
    while offset <= SECTOR - 12 and image[base + offset:base + offset + 12] != b'\xff' * 12:
        tag, group = image[base + offset], image[base + offset + 1]
        number, = struct.unpack_from('<H', image, base + offset + 2)
        length, following = struct.unpack_from('<HH', image, base + offset + 8)
        if following != offset + 12 + length:
            raise ValueError('PMM record chain is not contiguous at 0x%x' % offset)
        found.append((offset, tag, group, number,
                      bytes(image[base + offset + 12:base + offset + 12 + length])))
        offset = following
    return found


def aux_startup_reason(image):
    """The reason the firmware would read: the last valid record, or None."""
    value = None
    for _, tag, group, number, payload in records(image):
        if (group, number) == AUX_STARTUP_REASON and tag == 0xf4 and len(payload) == 2:
            value, = struct.unpack('<H', payload)
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--cdrive', type=Path, help='new raw C: image (boot0.vhd)')
    parser.add_argument('--pmm', type=Path, help='new raw PMM image (boot1.vhd)')
    parser.add_argument('--inspect', type=Path, help='report the AUX startup reason of a PMM image')
    args = parser.parse_args()
    if args.inspect:
        image = args.inspect.read_bytes()
        if len(image) != PMM_SIZE:
            parser.exit(2, 'a raw PMM image is %d bytes\n' % PMM_SIZE)
        print(json.dumps(dict(path=str(args.inspect), records=len(records(image)),
                              aux_startup_reason=aux_startup_reason(image))))
        return
    if not args.cdrive and not args.pmm:
        parser.error('nothing to do: give --cdrive, --pmm or --inspect')
    report = {}
    for name, path, data in (('cdrive', args.cdrive, b'\xff' * C_SIZE),
                             ('pmm', args.pmm, factory_pmm())):
        if path is None:
            continue
        try:
            with path.open('xb') as output:
                output.write(data)
        except OSError as error:
            parser.exit(2, str(error) + '\n')
        report[name] = dict(path=str(path), bytes=len(data),
                            sha256=hashlib.sha256(data).hexdigest())
    if 'pmm' in report:
        report['pmm']['aux_startup_reason'] = FORMAT_USER_AREA
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
