#!/usr/bin/env python3
"""Prepare a verified N-Gage v1 bundle. Inputs are never modified.

Format: 128-byte little-endian header, followed by core, extension, C: and
PMM bytes in that order. Header: magic[8], version:u32, profile:u32,
count:u32, header_size:u32, then four (DDR offset, length, CRC32) u32 triples;
remaining header bytes are zero. CRC32 uses the standard IEEE polynomial.
The companion JSON identifies the exact inputs and source hashes. The format
is provisional until the FPGA loader implements and tests it.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
SPECS = (
    ('core', 'build/firmware/nem4-factory/core.bin', 0x11c0000, 0, 'be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524'),
    ('extension', 'build/firmware/nem4-factory/extension.bin', 0x230000, 0x11c0000, 'cb6e0b39c90df00864fc21ee527624372b1e4f5c3ff3c985f397172d30446cf3'),
    ('cdrive', 'scratch/overnight/cdrive-11b.img', 0x400000, 0x1400000, 'af5017dcc0d4979ae9c7313a3a77295922009f08e26fbb559bd90d9539190a47'),
    ('pmm', 'scratch/overnight/pmm-aan.bin', 0x10000, 0x1800000, 'c7075d001311f5f122137fc891b2ade159fb39931810ae0d9965aea2a07e2496'),
)

def metadata(data):
    return hashlib.sha256(data).hexdigest(), zlib.crc32(data) & 0xffffffff

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', required=True, choices=('diagnostic-erased-pmm', 'diagnostic-seeded-pmm'))
    parser.add_argument('--output', type=Path, required=True, help='new bundle file; will not overwrite')
    args = parser.parse_args()
    dest = args.output.resolve()
    manifest = Path(str(dest) + '.json')
    # Opening exclusively avoids accidental replacement of firmware or old bundles.
    if dest.exists() or manifest.exists(): parser.error('output or companion manifest already exists')
    sections = []
    for name, rel, length, offset, expected in SPECS:
        if name == 'pmm' and args.profile == 'diagnostic-erased-pmm':
            data = b'\xff' * length
            source = 'generated erased PMM (not the seeded PMM)'
        else:
            path = ROOT / rel
            data = path.read_bytes()
            source = rel
            if len(data) != length or hashlib.sha256(data).hexdigest() != expected:
                raise SystemExit(f'{name}: input size or SHA-256 does not match audited profile')
        sha, crc = metadata(data)
        sections.append((dict(name=name, source=source, length=length, ddr_offset=offset, sha256=sha, crc32=f'{crc:08x}'), data))
    profile_id = 1 if args.profile == 'diagnostic-erased-pmm' else 2
    header = struct.pack('<8sIIII', b'NGAGEB1\0', 1, profile_id, 4, 128)
    for meta, _ in sections:
        header += struct.pack('<III', meta['ddr_offset'], meta['length'], int(meta['crc32'], 16))
    header = header.ljust(128, b'\0')
    record = {'format': 'ngage-bundle-v1-provisional', 'profile': args.profile,
              'warning': 'Synthetic SIM/PMM assumptions; not a validated physical phone. No FPGA loader implemented yet.',
              'sections': [meta for meta, _ in sections]}
    try:
        with dest.open('xb') as out:
            out.write(header)
            for _, data in sections: out.write(data)
        with manifest.open('x') as out: json.dump(record, out, indent=2); out.write('\n')
    except Exception:
        # Do not delete either file here: another process could own it.
        raise
    print(f'Prepared {dest} and {manifest}; original inputs unchanged')

if __name__ == '__main__': main()
