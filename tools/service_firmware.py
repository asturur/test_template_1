#!/usr/bin/env python3
"""Read-only oracle for the exact NEM-4 4.03 service pair.

The FPGA stores original scrambled payloads. This tool validates the bounded
container grammar and compares the assembled backing to the existing images;
it never rewrites firmware, user images or the original service containers.
"""
import argparse
import hashlib
import json
from pathlib import Path
import zlib

ROOT = Path(__file__).resolve().parents[1]
PROFILES = {
    'mcu': ('nem440.3c1', 18777938, 0x2DEF2, 2268, 0x7BC70477,
            'e948c435c977772a30ff2dd8ef608f7542a978c0acfd257bc0986925fd548690'),
    'ppm': ('nem440.326', 1361703, 0xD9, 167, 0xC3B897C7,
            'fd4126eeaddf5c0cd72a9961f51e283bd1ed4245106e20f01d5a5551e85fddc7'),
}
SEGMENTS = ((0, 0x700000, 0), (0x700000, 0x7F0000, 0x1300000),
            (0x2000000, 0x2400000, 0x700000), (0x4000000, 0x4800000, 0xB00000))
PPM_OWNED = ((0, 0x12C), (0x164, 0x10000), (0x700000, 0x76C000),
             (0x4730000, 0x4800000))
BACKING_SIZE = 0x13F0000


def offset(address, length):
    for lo, hi, base in SEGMENTS:
        if lo <= address < hi and 0 < length <= hi - address:
            return base + address - lo
    raise ValueError('record outside immutable firmware map')


def parse(data, kind, identify=True):
    """Parse exact bounded metadata/algorithm and checksummed data records.

    identify=False is used only by malformed-input tests to reach structural
    checks. Production verification always checks full length, CRC and SHA.
    """
    _, size, first, count, crc, sha = PROFILES[kind]
    if len(data) < 9 or data[0] != 0xA2:
        raise ValueError('bad prefix')
    pos = 9
    while True:
        if pos + 2 > len(data):
            raise ValueError('truncated TLV')
        tag, length = data[pos:pos+2]
        pos += 2
        if pos + length > len(data) or pos + length > first:
            raise ValueError('TLV bounds')
        pos += length
        if tag == 0xD3:
            if length != 64:
                raise ValueError('signature size')
            break
    if kind == 'mcu':
        if pos + 21 > len(data):
            raise ValueError('truncated algorithm preamble')
        preamble = data[pos:pos+21]
        if preamble != bytes.fromhex('2503323298260002dd9463557d01562000004000bf'):
            raise ValueError('unknown flashing algorithm')
        pos += 21 + int.from_bytes(preamble[7:10], 'big') + 66
    if pos != first:
        raise ValueError('unexpected first record offset')
    records = []
    while pos < len(data):
        if pos + 10 > len(data):
            raise ValueError('truncated record header')
        header = data[pos:pos+10]
        address = int.from_bytes(header[1:5], 'big')
        length = int.from_bytes(header[6:9], 'big')
        if header[0] != 0x14 or sum(header[1:]) % 256 != 255:
            raise ValueError('record header checksum/marker')
        if not 0 < length <= 8192:
            raise ValueError('record length')
        offset(address, length)
        payload = data[pos+10:pos+10+length]
        if len(payload) != length or (sum(payload) + header[5]) % 256:
            raise ValueError('payload length/checksum')
        if kind == 'ppm' and not any(lo <= address and address+length <= hi
                                     for lo, hi in PPM_OWNED):
            raise ValueError('PPM outside owned ranges')
        records.append((address, payload))
        pos += 10 + length
    if len(records) != count:
        raise ValueError('incomplete record coverage')
    if identify and (len(data) != size or
                     zlib.crc32(data) != crc or hashlib.sha256(data).hexdigest() != sha):
        raise ValueError('not the audited 4.03 profile')
    return records


def apply(image, records, kind):
    # Clear only this slot's ownership, just as an HDL reload does. The erased
    # personalization hole belongs to MCU's complement and remains FF.
    for lo, hi, _ in SEGMENTS:
        fragments = [(lo, hi)]
        if kind == 'mcu':
            for start, end in PPM_OWNED:
                fragments = [(a, b) for x, y in fragments for a, b in
                             ((x, min(y, start)), (max(x, end), y)) if a < b]
        else:
            fragments = [(max(lo, a), min(hi, b)) for a, b in PPM_OWNED
                         if max(lo, a) < min(hi, b)]
        for a, b in fragments:
            dest = offset(a, b-a)
            image[dest:dest+b-a] = b'\xff' * (b-a)
    for address, payload in records:
        fragments = [(address, address+len(payload))]
        if kind == 'mcu':
            for start, end in PPM_OWNED:
                fragments = [(a, b) for x, y in fragments for a, b in
                             ((x, min(y, start)), (max(x, end), y)) if a < b]
        for a, b in fragments:
            dest = offset(a, b-a)
            image[dest:dest+b-a] = payload[a-address:b-address]


def verify():
    parts = {kind: parse((ROOT/'firmware/NEM-04 v.04.03 N-GAGE'/spec[0]).read_bytes(), kind)
             for kind, spec in PROFILES.items()}
    expected = (ROOT/'build/firmware/nem4-factory/core.bin').read_bytes() + \
               (ROOT/'build/firmware/nem4-factory/extension.bin').read_bytes()
    results = []
    for order in (('mcu', 'ppm'), ('ppm', 'mcu'),
                  ('ppm', 'mcu', 'mcu'), ('mcu', 'ppm', 'ppm')):
        image = bytearray(b'\xff' * BACKING_SIZE)
        for kind in order:
            apply(image, parts[kind], kind)
        if image != expected:
            raise ValueError(f'assembled backing mismatch: {order}')
        results.append(list(order))
    return {'bytes_compared': len(expected), 'sha256': hashlib.sha256(expected).hexdigest(),
            'records': sum(map(len, parts.values())), 'passing_orders': results}


if __name__ == '__main__':
    argparse.ArgumentParser(description=__doc__).parse_args()
    print(json.dumps(verify(), indent=2))
