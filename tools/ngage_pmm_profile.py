#!/usr/bin/env python3
"""Add a synthetic DOS default to the audited native-formatted NEM-4 PMM.

Never overwrite an existing output. This deliberately supports one captured
native base, not arbitrary PMM dumps. Empty hand-built catalogs failed native
startup; preserve the native metadata until its dependencies are understood.
The DOS value is synthetic policy, not a recovered factory setting.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

SIZE = 65536
SOURCE_SHA = 'd355928744c3f4ba634c044fd7346367e750154e845756822fef08465747afef'


def build(source, dos_byte):
    if not 0 <= dos_byte <= 255:
        raise ValueError('synthetic DOS value must fit one byte')
    if len(source) != SIZE or hashlib.sha256(source).hexdigest() != SOURCE_SHA:
        raise ValueError('requires the audited native-formatted PMM base')
    image = bytearray(source)
    offset = 32
    seen = set()
    while image[offset:offset+12] != b'\xff'*12:
        if offset in seen or not 32 <= offset < 16384-12:
            raise ValueError('invalid PMM record chain')
        seen.add(offset)
        length, following = struct.unpack_from('<HH', image, offset+8)
        if following != offset+12+length:
            raise ValueError('unexpected PMM record extent')
        if image[offset+1] == 50 and struct.unpack_from('<H', image, offset+2)[0] == 1:
            raise ValueError('record50/1 already exists')
        offset = following
    if offset+14 > 16384 or image[offset:offset+14] != b'\xff'*14:
        raise ValueError('no erased room for the new PMM record')
    record = bytes((0xf0, 50, 1, 0, 0x55, 0xff, 0xff, 0xff))
    record += struct.pack('<HH', 2, offset+14)
    image[offset:offset+14] = record + bytes((4, dos_byte))
    return bytes(image)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--synthetic-dos-byte', required=True,
                        type=lambda text: int(text, 0))
    args = parser.parse_args()
    try:
        source = args.source.read_bytes()
        image = build(source, args.synthetic_dos_byte)
        with args.output.open('xb') as output:
            output.write(image)
    except (ValueError, OSError) as error:
        parser.exit(2, str(error) + '\n')
    print(json.dumps(dict(path=str(args.output), bytes=len(image),
                          sha256=hashlib.sha256(image).hexdigest(), source_sha256=SOURCE_SHA,
                          group=50, record=1, payload_hex=bytes((4,args.synthetic_dos_byte)).hex(),
                          policy='synthetic DOS byte; factory meaning unverified',
                          validation='byte0 passed matched150s native boot; durability unverified')))


if __name__ == '__main__':
    main()
