#!/usr/bin/env python3
"""List/extract NEM-4 LFFS using its own ROM filesystem in a read-only NGVM copy.

Requires an existing NGVM reference checkout, ARM GCC, Unicorn and the user's
exact NEM-4 SYM.ROM. It never mounts or changes the input image. NGVM replaces
the kernel only; the original guest file server implements the filesystem.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PureWindowsPath
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
ROM_SHA = 'afc1cc8b693f2b68d23ca203aa4d4eb4266baad4ab718f013a33b915d39574ef'
MAGIC = bytes.fromhex('603b3b50')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def guest_path(encoded):
    value = bytes.fromhex(encoded).decode('utf-16-le', errors='strict')
    path = PureWindowsPath(value)
    if path.drive.lower() != 'c:' or not path.is_absolute():
        raise ValueError('unexpected guest drive/path')
    parts = path.parts[1:]
    if not parts or any(p in ('.', '..') or ':' in p or '\x00' in p for p in parts):
        raise ValueError('unsafe guest path')
    return value, Path(*parts)


def parse_capture(text):
    entries, files, errors = [], {}, []
    done = None
    for line in text.splitlines():
        if line.startswith('NGFS_ENTRY '):
            _, att, size, encoded = line.split()
            name, local = guest_path(encoded)
            entries.append({'path': name, 'relative_path': local.as_posix(),
                            'attributes': int(att, 16), 'bytes': int(size)})
        elif line.startswith('NGFS_FILE '):
            _, key, size, encoded = line.split()
            name, local = guest_path(encoded)
            if key in files or int(size) < 0 or int(size) > 4194304:
                raise ValueError('duplicate/oversized file record')
            files[key] = {'path': name, 'relative_path': local.as_posix(),
                          'bytes': int(size), 'data': bytearray(), 'complete': False}
        elif line.startswith('NGFS_DATA '):
            _, key, offset, encoded = line.split()
            item = files[key]
            if item['complete'] or int(offset) != len(item['data']):
                raise ValueError('non-contiguous or late file chunk')
            item['data'].extend(bytes.fromhex(encoded))
            if len(item['data']) > item['bytes']:
                raise ValueError('file data exceeds declared size')
        elif line.startswith('NGFS_END '):
            item = files[line.split()[1]]
            if item['complete'] or len(item['data']) != item['bytes']:
                raise ValueError('incomplete/duplicate file completion')
            item['complete'] = True
        elif line.startswith(('NGFS_ERROR ', 'NGFS_DIRERR ')):
            errors.append(line)
        elif line.startswith('NGFS_OPEN ') and line.split()[1] != '0':
            errors.append(line)
        elif line.startswith('NGFS_CONNECT ') and line.split()[1] != '0':
            errors.append(line)
        elif line.startswith('NGFS_DONE '):
            done = int(line.split()[1])
    if done is None or done != len(entries):
        raise ValueError('missing/mismatched completed directory walk')
    if errors or any(not x['complete'] for x in files.values()):
        raise ValueError('guest filesystem extraction failed: ' + '; '.join(errors))
    seen = set()
    for item in files.values():
        key = item['relative_path'].casefold()
        if key in seen:
            raise ValueError('duplicate output path')
        seen.add(key)
    return entries, list(files.values())


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('image', type=Path)
    ap.add_argument('--out', required=True, type=Path)
    ap.add_argument('--rom', type=Path, default=ROOT/'firmware/SYM.ROM')
    ap.add_argument('--reference', type=Path,
                    default=ROOT/'scratch/fresh-c-investigation/ngvm4')
    ap.add_argument('--all-files', action='store_true', help='extract all files, not just logs/text')
    ap.add_argument('--reuse-work', type=Path, help='reuse a validated private reader build from an earlier extraction')
    args = ap.parse_args()
    image, out, rom, ref = (p.resolve() for p in (args.image, args.out, args.rom, args.reference))
    if out.exists():
        ap.error('output must not already exist')
    raw = image.read_bytes()
    if len(raw) != 4194304:
        ap.error('requires exactly4 MiB raw NEM-4 C: bytes, not an NGA/container/FAT image')
    source_sha = hashlib.sha256(raw).hexdigest()
    blocks = sum(raw[i+4:i+8] == MAGIC for i in range(0, len(raw), 65536))
    manifest = {'source': str(image), 'source_sha256': source_sha,
                'bytes': len(raw), 'lffs_block_headers': blocks,
                'method': 'original guest filesystem under private NGVM read-only media',
                'all_files': args.all_files}
    if all(x == 255 for x in raw):
        out.mkdir(parents=True)
        manifest.update(status='erased; no filesystem or files', entries=[], files=[])
        (out/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
        print('Erased image: no filesystem/logs; input unchanged.')
        return
    if not blocks:
        ap.error('no recognized LFFS header; refusing to format/repair an unknown image')
    if digest(rom) != ROM_SHA:
        ap.error('guest API ordinals/layout validated only for the specified NEM-4 ROM hash')
    for name in ([] if args.reuse_work else ['sw/kernel/drive.c', 'sw/kernel/Makefile', 'tools/ngvm/ngvm.py']):
        if not (ref/name).is_file():
            ap.error('missing existing NGVM reference file: '+name)
    if not shutil.which('arm-none-eabi-gcc'):
        ap.error('ARM GCC must be installed')
    out.mkdir(parents=True)
    work = args.reuse_work.resolve() if args.reuse_work else out/'.work'
    expected_launch = (ROOT/'tools/lffs_reader/launch.c').read_text()
    if args.all_files:
        expected_launch = '#define NGFS_ALL_FILES 1\n'+expected_launch
    if args.reuse_work:
        prepared = json.loads((work/'prepared.json').read_text())
        expected_sha = hashlib.sha256(expected_launch.encode()).hexdigest()
        if prepared['reader_sha256'] != expected_sha or prepared['all_files'] != args.all_files:
            raise ValueError('prepared reader options/source mismatch')
        for name, key in [('sw/kernel/launch.c', 'reader_sha256'),
                          ('sw/kernel/drive.c', 'guarded_drive_sha256'),
                          ('build/kernel/kernel.elf', 'kernel_sha256')]:
            if digest(work/name) != prepared[key]:
                raise ValueError('prepared reader changed: '+name)
    else:
        for name in ['sw', 'tools']:
            shutil.copytree(ref/name, work/name, ignore=shutil.ignore_patterns('__pycache__'))
        (work/'sw/kernel/launch.c').write_text(expected_launch)
        drive = work/'sw/kernel/drive.c'
        source = drive.read_text()
        old = '    if (!t) r = KErrBadHandle;'
        old_erase = '    if (!media[l->unit].max) r = KErrNotReady;'
        if source.count(old) != 1 or source.count(old_erase) != 1:
            raise ValueError('reference changed; cannot safely install read-only media guards')
        source = source.replace(old, '    if (write && l->unit == 0) r = KErrAccessDenied;\n    else if (!t) r = KErrBadHandle;')
        source = source.replace(old_erase, '    if (l->unit == 0) r = KErrAccessDenied;\n    else if (!media[l->unit].max) r = KErrNotReady;')
        drive.write_text(source)
        with (out/'build.log').open('wb') as log:
            subprocess.run(['make', '-C', str(work/'sw/kernel')], stdout=log,
                           stderr=subprocess.STDOUT, check=True, timeout=120)
        prepared = {'reader_sha256': digest(work/'sw/kernel/launch.c'),
                    'guarded_drive_sha256': digest(drive),
                    'kernel_sha256': digest(work/'build/kernel/kernel.elf'),
                    'all_files': args.all_files}
        (work/'prepared.json').write_text(json.dumps(prepared, indent=2)+'\n')
    private_image = out/'input.vhd'
    private_image.write_bytes(raw)
    with (out/'guest.log').open('wb') as log:
        subprocess.run([sys.executable, '-u', str(work/'tools/ngvm/ngvm.py'),
                        '--rom', str(rom), '--save', str(private_image),
                        '--seconds', '3', '--mips', '100'], stdout=log,
                       stderr=subprocess.STDOUT, check=True, timeout=120)
    if digest(private_image) != source_sha or digest(image) != source_sha:
        raise ValueError('image changed; reject extraction')
    text = (out/'guest.log').read_text()
    if not re.search(r'save: loaded 4194304 bytes, 0 writes to C:', text):
        raise ValueError('guest did not confirm zero C: writes')
    entries, files = parse_capture(text)
    for item in files:
        target = out/'files'/item['relative_path']
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('xb') as f:
            f.write(item.pop('data'))
        item['sha256'] = digest(target)
    manifest.update(status='complete', rom_sha256=ROM_SHA, entries=entries, files=files,
                    input_unchanged=True, guest_c_writes=0,
                    reader_sha256=digest(work/'sw/kernel/launch.c'),
                    guarded_drive_sha256=digest(work/'sw/kernel/drive.c'))
    (out/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print(f'Listed {len(entries)} entries; extracted {len(files)} files; source unchanged.')


if __name__ == '__main__':
    main()
