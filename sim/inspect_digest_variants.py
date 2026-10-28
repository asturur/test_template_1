#!/usr/bin/env python3
"""Find plausible embedded MD5 range descriptors in supplied firmware images."""
import hashlib
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]


def scan(image):
    path = ROOT/image['path']
    data = path.read_bytes()
    sha = hashlib.sha256(data).hexdigest()
    if sha != image['sha256'] or len(data) != image['bytes']:
        raise ValueError(f"inventory mismatch: {path}")
    base = image['header']['base']
    candidates = []
    for offset in range(0,min(len(data)-24,0x20000),4):
        start,end = struct.unpack_from('<II',data,offset)
        lo,hi = start-base,end-base+1
        if not (0 <= lo < hi <= 0x4000000 and hi-lo >= 0x100000 and lo%0x1000 == 0 and hi%0x1000 == 0):
            continue
        expected = data[offset+8:offset+24]
        if not any(expected):
            continue
        actual = hashlib.md5(data[lo:hi]).digest() if hi <= len(data) else None
        candidates.append(dict(descriptor_offset=offset,virtual_start=start,virtual_end_inclusive=end,
            file_start=lo,file_end_exclusive=hi,bytes=hi-lo,expected_md5=expected.hex(),
            actual_md5=actual.hex() if actual else None,matches=expected==actual if actual else None,
            core_file_contains_range=hi <= len(data)))
    references=[]
    for pc in range(0,min(len(data)-4,0x8000),4):
        word=struct.unpack_from('<I',data,pc)[0]
        # ARM LDR literal, any condition and either sign. A raw aligned scan
        # is evidence of references, not proof that each word is executed.
        if word & 0x0f7f0000 != 0x051f0000:
            continue
        literal=pc+8+((word & 0xfff) if word & (1<<23) else -(word & 0xfff))
        if 0 <= literal <= len(data)-4:
            target=struct.unpack_from('<I',data,literal)[0]
            if target in (0x8f00,0x8f18):
                references.append(dict(instruction_offset=pc,literal_offset=literal,target=target))
    return dict(path=image['path'],bytes=len(data),sha256=sha,candidates=candidates,
                candidate_literal_references=references)


def main():
    inventory_path=ROOT/'build/firmware/inventory.json'
    inventory=json.loads(inventory_path.read_text())
    report=dict(method='aligned early-ROM candidate scan; address range and digest shape are inferred',
                scan_bytes=0x20000,minimum_range_bytes=0x100000,
                inventory_sha256=hashlib.sha256(inventory_path.read_bytes()).hexdigest(),
                images=[scan(image) for image in inventory['images']],
                scope='NEM-4 descriptor executed in simulation; QD candidates not executed or proven boot descriptors')
    output=ROOT/'build/firmware/digest-variants.json'
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(report,indent=2)+'\n')
    for image in report['images']:
        print(image['path'])
        for item in image['candidates']:
            print(f"  descriptor 0x{item['descriptor_offset']:x}: expected {item['expected_md5']}, actual {item['actual_md5']}, match={item['matches']}")
    print('Report:',output)


if __name__=='__main__':
    main()
