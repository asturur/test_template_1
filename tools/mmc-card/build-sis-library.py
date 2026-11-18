#!/usr/bin/env python3
"""Build standard-capacity FAT16 installer libraries; never modify source packages."""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import struct
import subprocess
import zipfile
import zlib
import mkcard

ROOT = Path(__file__).resolve().parents[2]
EPOCH = 1041379200


def sha(path):
    with path.open('rb') as stream:
        digest = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024*1024), b''):
            digest.update(chunk)
        return digest.hexdigest()


def rar_members(path):
    """List RAR4 headers, including solid archives, without running/decompressing."""
    raw = path.read_bytes()
    if raw[:7] != b'Rar!\x1a\x07\x00':
        raise ValueError('Unsupported archive signature: ' + str(path))
    position, members = 7, []
    while position + 7 <= len(raw):
        crc, kind, flags, length = struct.unpack_from('<HBHH', raw, position)
        if length < 7 or position + length > len(raw):
            raise ValueError('Truncated RAR header')
        if zlib.crc32(raw[position+2:position+length]) & 0xffff != crc:
            raise ValueError('RAR header checksum mismatch')
        packed = struct.unpack_from('<I', raw, position+7)[0] if flags & 0x8000 else 0
        if kind == 0x74:
            if length < 32:
                raise ValueError('Truncated RAR file header')
            name_length = struct.unpack_from('<H', raw, position+26)[0]
            start = position+32+(8 if flags & 0x100 else 0)
            if start + name_length > position + length:
                raise ValueError('Truncated RAR filename')
            name = raw[start:start+name_length].split(b'\0')[0].decode('cp1252')
            members.append(name)
            if flags & 0x100:
                packed |= struct.unpack_from('<I', raw, position+32)[0] << 32
        position += length + packed
        if position > len(raw):
            raise ValueError('Truncated RAR data')
        if kind == 0x7b:
            break
    return members


def card_path(relative, index):
    # Native Manager discovery is already verified for root-level installers.
    # Short names keep all 383 entries within the original 512-entry root.
    parts = relative.parts
    if len(parts) > 1 and parts[0].lower().startswith('ultimate_sis'):
        parts = parts[1:]
    title = parts[0] if len(parts) > 1 else Path(parts[0]).stem
    if index > 9999:
        raise ValueError('Short-name library supports up to 9,999 installers')
    prefix = ''.join(c for c in title.upper() if c.isascii() and c.isalnum())[:4].ljust(4, 'X')
    return Path(prefix + f'{index:04d}' + '.SIS')


def collect(source, stage):
    stage.mkdir(parents=True, exist_ok=False)
    rows, archives, occupied = [], [], set()

    def add(relative, content, origin):
        dest = card_path(relative, len(rows)+1)
        if str(dest).casefold() in occupied:
            dest = dest.with_name(dest.stem + '-' + hashlib.sha256(origin.encode()).hexdigest()[:8] + dest.suffix)
        key = str(dest).casefold()
        if key in occupied or len('E:\\' + str(dest).replace('/', '\\')) > 256:
            raise ValueError('Card filename collision or overlong path')
        occupied.add(key)
        target = stage/dest
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
        os.utime(target, (EPOCH, EPOCH))
        rows.append(dict(source=origin, card_path=dest.as_posix(), bytes=len(content),
                         sha256=hashlib.sha256(content).hexdigest()))

    for path in sorted(source.rglob('*')):
        if path.is_symlink():
            raise ValueError('Source symlinks are not supported')
        if not path.is_file():
            continue
        relative = path.relative_to(source)
        if path.suffix.lower() in ('.sis', '.sisx'):
            add(relative, path.read_bytes(), str(relative))
        elif path.suffix.lower() in ('.zip', '.rar'):
            if zipfile.is_zipfile(path):
                with zipfile.ZipFile(path) as archive:
                    members = [m.filename for m in archive.infolist() if not m.is_dir()]
                    selected = [m for m in members if Path(m).suffix.lower() in ('.sis', '.sisx')]
                    for member in selected:
                        if archive.getinfo(member).file_size > 64*1024*1024:
                            raise ValueError('Oversized archived SIS')
                        add(relative.parent/Path(member.replace('\\', '/')).name,
                            archive.read(member), str(relative)+'!'+member)
            else:
                members = rar_members(path)
                selected = [m for m in members if Path(m).suffix.lower() in ('.sis', '.sisx')]
                for member in selected:
                    content = subprocess.check_output(['bsdtar', '-xOf', str(path), member])
                    add(relative.parent/Path(member.replace('\\', '/')).name,
                        content, str(relative)+'!'+member)
            archives.append(dict(source=str(relative), sha256=sha(path), members=len(members),
                                 sis_members=selected))
    readme = ('SIS INSTALLER LIBRARY\r\n\r\n'
              'Installers are at the card root for native Tools > Manager discovery.\r\n'
              'INDEX.TXT maps short card names to original game/package names.\r\n'
              'All original packages are preserved, including different phone/OS versions.\r\n'
              'Some packages target newer phones and may not install on this N-Gage.\r\n'
              'No package was executed or automatically installed.\r\n'
              'Today the core forces MMC read-only. Future writable MMC support\r\n'
              'can allow installation on E: when the package permits it.\r\n'
              'C: remains the original 4 MiB flash.\r\n')
    (stage/'README.TXT').write_text(readme)
    (stage/'INDEX.TXT').write_text('\r\n'.join(r['card_path']+' = '+r['source'] for r in rows)+'\r\n')
    for path in [stage/'README.TXT', stage/'INDEX.TXT']:
        os.utime(path, (EPOCH, EPOCH))
    return rows, archives


def build(stage, output, inventory, size_mb=1024, read_only=False):
    for row in inventory['packages']:
        path = stage/row['card_path']
        if path.stat().st_size != row['bytes'] or sha(path) != row['sha256']:
            raise ValueError('Staged SIS differs from its source inventory: '+str(path))
    # Extend geometry locally; leave the pinned donor builder unchanged.
    mkcard.SIZES = dict(mkcard.SIZES)
    mkcard.SIZES.update({256: (32, 5), 512: (64, 6), 1024: (128, 7)})
    spc = 8 if size_mb <= 256 else 16 if size_mb == 512 else 32
    cluster_bytes = spc*512
    mkcard.SPC, mkcard.CLUSTER = spc, cluster_bytes
    geometry = mkcard.geometry(size_mb)
    assert geometry['bits'] == 16 and geometry['blocks']*512+512 <= 1073742336
    files, dirs, notes = mkcard.plan_tree(str(stage), True)
    need, roots = mkcard.usage(files, dirs)
    # The donor estimator reserves LFN slots even for uppercase 8.3 names.
    # This library deliberately uses only such names in a flat root.
    assert dirs == {()} and all(re.fullmatch(r'[A-Z0-9]{1,8}\.[A-Z0-9]{1,3}', name) for name, _ in files[()])
    roots = len(files[()])
    if need > geometry['clusters'] or roots > mkcard.ROOT_ENTRIES:
        raise ValueError('Installer library exceeds card capacity')
    output.parent.mkdir(parents=True, exist_ok=True)
    image = Path(str(output)+'.img.part')
    if image.exists() or Path(str(output)+'.mmc').exists():
        raise ValueError('Refusing to overwrite an existing output')
    try:
        image.write_bytes(mkcard.blank_card(geometry))
        mkcard.fill(str(image), files, dirs, EPOCH)
        data = image.read_bytes()
        free = mkcard.verify(data, files, dirs)
        csd = bytearray(mkcard.folder_csd(geometry['mult']))
        if read_only:
            csd[14] |= 0x10  # CSD temporary write protection, guest-visible.
        mkcard.write_card(str(output), data, mkcard.folder_cid(output.name, EPOCH),
                          csd, bytes.fromhex('00ff8000'))
    finally:
        image.unlink(missing_ok=True)
    report = dict(inventory, filesystem='FAT16', sectors_per_cluster=spc,
                  cluster_bytes=cluster_bytes, geometry=geometry, free_bytes=free*cluster_bytes,
                  readback='PASS: every filename, directory and source byte compared', notes=notes,
                  core_readonly=True, csd_write_protected=read_only, native_mount_tested=False,
                  images={})
    for suffix in ['.mmc', '.img']:
        path = Path(str(output)+suffix)
        report['images'][path.name] = dict(bytes=path.stat().st_size, sha256=sha(path))
    raw = Path(str(output)+'.img')
    raw.unlink()  # Rebuildable duplicate; deliver only the MMC image.
    report['images'][raw.name]['retained'] = False
    Path(str(output)+'.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(dict(card=str(output)+'.mmc', sis_count=len(report['packages']),
                         free_MiB=report['free_bytes']/1048576, verified=True)), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--stage', type=Path, default=ROOT/'runtime/mmc/ultimate-sis-1gb')
    parser.add_argument('--output', type=Path, default=ROOT/'build/mmc/ultimate-sis-1gb')
    parser.add_argument('--build-only', action='store_true')
    parser.add_argument('--size-mb', type=int, choices=[64,128,256,512,1024], default=1024)
    parser.add_argument('--read-only', action='store_true', help='Advertise temporary write protection in the MMC CSD')
    args = parser.parse_args()
    if args.build_only:
        inventory = json.loads((args.stage.parent/(args.stage.name+'.json')).read_text())
        build(args.stage, args.output, inventory, args.size_mb, args.read_only)
    else:
        rows, archives = collect(args.source.resolve(), args.stage)
        inventory = dict(source=str(args.source.resolve()), packages=rows, archives=archives,
                         sis_bytes=sum(r['bytes'] for r in rows), scope='Original installer bytes only; no execution, installation or phone compatibility claim')
        (args.stage.parent/(args.stage.name+'.json')).write_text(json.dumps(inventory, indent=2)+'\n')
        print(json.dumps(dict(sis_count=len(rows), sis_MiB=inventory['sis_bytes']/1048576,
                              stage=str(args.stage))), flush=True)


if __name__ == '__main__':
    main()
