#!/usr/bin/env python3
"""Read-only inventory of the audited NEM-4 ADSP update and RAM load records.

Mappings are recovered from record structure and code cross-references, not
proof of the DA250 boot ROM implementation or a complete DSP emulator.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_IMAGE = ROOT / 'firmware/MCU/extracted/products/NEM-4/E403A400H450.USB'
SHA256 = '0be93de04ebccd676d34ceaa2b9f4a901b3d0941565bc7b0f795e78ba8866429'
FLASH_BASE = 0x400000
RAM_BYTES = 0x40000


def inspect_image(data):
    """Require the audited image; keep addresses and unknown regions explicit."""
    if len(data) != 1506378 or hashlib.sha256(data).hexdigest() != SHA256:
        raise ValueError('not the audited original ADSP update')
    records = []
    occupied = bytearray(RAM_BYTES)
    ram = bytearray(RAM_BYTES)
    pos = 0x1000
    while pos + 8 <= len(data):
        word_address, words = struct.unpack_from('>II', data, pos)
        if word_address == words == 0xffffffff:
            break
        length = words * 2
        address = word_address * 2
        end = pos + 8 + length
        if not words or address + length > RAM_BYTES or end > len(data):
            raise ValueError('RAM load record outside bounds')
        if any(occupied[address:address + length]):
            raise ValueError('overlapping RAM load records')
        ram[address:address + length] = data[pos + 8:end]
        occupied[address:address + length] = bytes([1]) * length
        records.append(dict(index=len(records), header_offset=pos, source_offset=pos + 8,
                            destination_word=word_address, destination_byte=address,
                            words=words, bytes=length))
        pos = end
    if len(records) != 17 or pos != 0x17698:
        raise ValueError('unexpected RAM load record coverage')
    vectors = []
    first = records[0]
    if first['destination_byte'] != 0x100 or first['bytes'] != 256:
        raise ValueError('unexpected vector record')
    for index in range(32):
        source = first['source_offset'] + index * 8
        target = int.from_bytes(data[source + 1:source + 4], 'big')
        owner = 'unresolved'
        record_index = None
        if FLASH_BASE <= target < FLASH_BASE + len(data):
            owner = 'external_flash_candidate'
        for record in records:
            if record['destination_byte'] <= target < record['destination_byte'] + record['bytes']:
                owner = 'loaded_ram'
                record_index = record['index']
                break
        vectors.append(dict(index=index, source_offset=source, target=target,
                            owner=owner, record=record_index))
    manifest = dict(source_sha256=SHA256, source_bytes=len(data), source_modified=False,
                    flash_byte_base_candidate=FLASH_BASE, flash_capacity_bytes=0x200000,
                    unread_flash_tail='not supplied; do not treat as observed erased data',
                    load_table_offset=0x1000, load_table_end=pos,
                    load_table_format='big-endian32 destination word address and16-bit-word count',
                    ram_bytes=RAM_BYTES, ram_loaded_bytes=sum(occupied),
                    ram_holes='zero fill is an analysis placeholder, not observed reset contents',
                    records=records, vectors=vectors,
                    boot_execution_verified=False, arm_core_evidence=False)
    return manifest, bytes(ram), bytes(occupied)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', nargs='?', type=Path, default=DEFAULT_IMAGE)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    original = args.image.read_bytes()
    manifest, ram, occupied = inspect_image(original)
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / 'image.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (args.out / 'loaded-ram.bin').write_bytes(ram)
    (args.out / 'loaded-ram-valid.bin').write_bytes(occupied)
    assert args.image.read_bytes() == original
    print(f'PASS ADSP inventory:17 RAM records,{manifest["ram_loaded_bytes"]} loaded bytes,'
          f'32 vectors, reset target{manifest["vectors"][0]["target"]:06X}; source unchanged')


if __name__ == '__main__':
    main()
