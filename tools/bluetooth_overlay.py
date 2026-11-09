#!/usr/bin/env python3
"""Build a private Bluetooth_Compatibility.ngo from original NEM-4 service files."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import zlib

import nos_overlay as ngo
import service_firmware as svc


def build(mcu, ppm, output):
    raw = bytearray(b'\xff' * svc.BACKING_SIZE)
    for kind, path in [('mcu', mcu), ('ppm', ppm)]:
        svc.apply(raw, svc.parse(path.read_bytes(), kind), kind)
    if hashlib.md5(ngo.decode(raw)[0x9000:0x11b5000]).digest() != ngo.DIGEST:
        raise ValueError('stock decoded digest mismatch')
    compiler = shutil.which('arm-none-eabi-gcc')
    if not compiler:
        raise ValueError('arm-none-eabi-gcc is required')
    source = ngo.ROOT / 'firmware_overlays/bluetooth'
    work = output.parent / 'bluetooth-build'
    work.mkdir(parents=True, exist_ok=True)
    flags = ['-marm', '-march=armv4t', '-Os', '-ffreestanding', '-fno-builtin',
             '-fno-common', '-fno-pic', '-fno-tree-loop-distribute-patterns',
             '-Wall', '-Wextra', '-Werror']
    offsets = work / 'offsets.c'
    offsets.write_text('#include "bt_hci.h"\n'
                       'char size[sizeof(struct bt_st)];\n'
                       'char out[__builtin_offsetof(struct bt_st,out)];\n'
                       'char full[__builtin_offsetof(struct bt_st,ring_full)];\n')
    subprocess.run([compiler, *flags, '-I', str(source), '-c', str(offsets),
                    '-o', str(work / 'offsets.o')], check=True)
    symbols = subprocess.check_output(['arm-none-eabi-nm', '-S', str(work / 'offsets.o')], text=True)
    sizes = {parts[3]: int(parts[1], 16) for line in symbols.splitlines()
             if len(parts := line.split()) == 4}
    defines = [f'-DBT_ST_SIZE={sizes["size"]}', f'-DBT_ST_OUT={sizes["out"]}',
               f'-DBT_ST_FULL={sizes["full"]}']
    for name in ('bt_hci.c', 'bt_glue.S'):
        subprocess.run([compiler, *flags, *defines, '-c', str(source / name),
                        '-o', str(work / (name + '.o'))], check=True)
    subprocess.run([compiler, '-nostdlib', '-static', f'-Wl,-T,{source / "bt.ld"}',
                    '-Wl,--build-id=none', '-o', str(work / 'bt.elf'),
                    str(work / 'bt_glue.S.o'), str(work / 'bt_hci.c.o')], check=True)
    patches = {}
    for section, offset in [('.hook', 0x3f1cd0), ('.objsize', 0x3f28b0), ('.text', 0x11b4600)]:
        path = work / (section[1:] + '.bin')
        subprocess.run(['arm-none-eabi-objcopy', '-O', 'binary', '-j', section,
                        str(work / 'bt.elf'), str(path)], check=True)
        payload = path.read_bytes()
        if len(payload) % 4:
            raise ValueError('unaligned ARM payload')
        if section == '.text' and raw[offset:offset + len(payload)] != b'\xff' * len(payload):
            raise ValueError('Bluetooth payload area not erased')
        for i in range(0, len(payload), 4):
            old = struct.unpack_from('<I', raw, offset + i)[0]
            new = struct.unpack_from('<I', payload, i)[0]
            if old != new:
                patches[offset + i] = (old, new)
    # Shared descriptor: either NOS or BT requires the primary skip. The HDL
    # keeps it until both selectors are OFF; original expected digest is intact.
    for offset in (0x8f18, 0x8f1c):
        patches[offset] = (struct.unpack_from('<I', raw, offset)[0], 0xffffffff)
    records = [(offset, *values) for offset, values in sorted(patches.items())]
    if len(records) > ngo.MAX_RECORDS:
        raise ValueError('Bluetooth overlay exceeds staging BRAM')
    body = b''.join(struct.pack('<III', *record) for record in records)
    header = (struct.pack('<7I', ngo.MAGIC, 1, 2, len(records), zlib.crc32(body),
                          svc.PROFILES['mcu'][4], svc.PROFILES['ppm'][4]) + ngo.DIGEST
              + struct.pack('<4I', 64 + len(body), 0, 12, 0))
    package = header + struct.pack('<I', zlib.crc32(header)) + body
    ngo.inspect(package, overlay_id=2)
    active = bytearray(raw)
    for offset, old, new in records:
        struct.pack_into('<I', active, offset, new)
    assert active[0x8f20:0x8f30] == raw[0x8f20:0x8f30]
    for offset, old, new in records:
        struct.pack_into('<I', active, offset, old)
    assert active == raw
    output.write_bytes(package)
    report = {'name': 'Bluetooth Compatibility', 'file': output.name, 'format': 'NGO1',
              'overlay_id': 2, 'records': len(records), 'bytes': len(package),
              'sha256': hashlib.sha256(package).hexdigest(), 'skip_primary_checksum': True,
              'original_files_modified': False, 'off_restores_original': True,
              'radio_peer_supported': False,
              'inputs': {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in (mcu, ppm)}}
    output.with_suffix('.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mcu', type=Path)
    parser.add_argument('--ppm', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--inspect', type=Path)
    args = parser.parse_args()
    if args.inspect:
        print(json.dumps({'records': len(ngo.inspect(args.inspect.read_bytes(), overlay_id=2))}))
        return
    if not all((args.mcu, args.ppm, args.output)):
        parser.error('--mcu, --ppm and --output required')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    print(json.dumps(build(args.mcu, args.ppm, args.output), indent=2))


if __name__ == '__main__':
    main()
