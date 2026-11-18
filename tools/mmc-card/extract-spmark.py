#!/usr/bin/env python3
"""Extract this old SIS's ordinary files as data; reject installer logic.

Record layout checked against local EKA2L1 loader/sis_old.{h,cpp}.
This is deliberately not a general SIS installer or dependency resolver.
"""
from pathlib import Path, PureWindowsPath
import hashlib
import json
import os
import struct
import sys
import zlib

if len(sys.argv) not in (2, 3):
    raise SystemExit('Usage: extract-spmark.py SOURCE_SIS [OUTPUT_FOLDER]')
source = Path(sys.argv[1]).resolve()
work = (Path(sys.argv[2]).resolve() if len(sys.argv) == 3 else
        Path(__file__).resolve().parents[2] / 'runtime/mmc')
raw = source.read_bytes()
u16 = lambda off: struct.unpack_from('<H', raw, off)[0]
u32 = lambda off: struct.unpack_from('<I', raw, off)[0]
def span(off, length):
    if off < 0 or length < 0 or off + length > len(raw):
        raise ValueError('SIS range outside file')
    return raw[off:off + length]
def string(off, length):
    return span(off, length).decode('utf-16le')

if len(raw) < 100 or (u32(4), u32(8)) != (0x10003a12, 0x10000419):
    raise ValueError('Expected old Series 60 SIS')
if u16(18) != 1:
    raise ValueError('Only this single-language package is supported')
position = u32(52)
records = []
outputs = set()
for i in range(u16(20)):
    record, kind, detail, sl, sp, dl, dp = struct.unpack('<7I', span(position, 28))
    if record != 0 or kind not in (0, 1):
        raise ValueError('Installer logic, variants or special files require a real installer')
    packed_size, pointer, original = struct.unpack('<3I', span(position + 28, 12))
    position += 48
    destination = string(dp, dl)
    payload = span(pointer, packed_size)
    if original > 32 * 1024 * 1024:
        raise ValueError('Oversized payload')
    if not u16(36) & 8:
        decoder = zlib.decompressobj()
        payload = decoder.decompress(payload, original + 1)
        if not decoder.eof or decoder.unused_data or decoder.unconsumed_tail:
            raise ValueError('Invalid compressed payload')
    if len(payload) != original:
        raise ValueError('Payload length differs from SIS')
    if kind == 0:
        path = PureWindowsPath(destination)
        if path.drive.upper() not in ('!:', 'E:') or not path.root:
            raise ValueError('Payload requires a different install drive')
        parts = path.parts[1:]
        if not parts or any(p in ('.', '..') or ':' in p for p in parts):
            raise ValueError('Unsafe destination')
        target = work / 'extracted-files' / Path(*parts)
    else:
        # Preserve installer messages outside the card; never interpret them.
        target = work / 'installer-text' / ('%02d.txt' % i)
    folded = str(target).casefold()
    if folded in outputs:
        raise ValueError('Case-insensitive destination collision')
    outputs.add(folded)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(payload)
    os.utime(target, (1041379200, 1041379200))
    records.append(dict(record=i, type=kind, detail=detail, destination=destination,
                        output=str(target.relative_to(work)), bytes=len(payload),
                        sha256=hashlib.sha256(payload).hexdigest()))
installer = work / 'files' / 'SPMARK.SIS'
installer.parent.mkdir(exist_ok=True)
installer.write_bytes(raw)
os.utime(installer, (1041379200, 1041379200))
(work / 'empty-files').mkdir(exist_ok=True)
manifest = dict(source=str(source), bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                scope='Data extraction only; no installer registration, execution or hardware test',
                records=records)
(work / 'extraction.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Extracted %d application files and preserved %d installer messages' %
      (sum(r['type'] == 0 for r in records), sum(r['type'] == 1 for r in records)))
