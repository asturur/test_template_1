#!/usr/bin/env python3
"""Create/inspect NGA saves and split/join raw N-Gage C:/PMM images.

The image has a 512-byte header followed by raw C: (4 MiB) and PMM (64 KiB).
It is separate from the immutable bundle. HDL save/restore is simulation-tested;
real MiSTer persistence and power-cycle recovery remain unverified.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import struct
import zlib

HEADER=512
C_LEN=0x400000
PMM_LEN=0x10000
MAGIC=b'NGSAVE1\0'
SIZE=HEADER+C_LEN+PMM_LEN

def parse_bundle(path):
    b=path.read_bytes()
    if len(b)<128: raise ValueError('truncated bundle')
    magic,version,profile,count,head=struct.unpack_from('<8sIIII',b)
    if magic!=b'NGAGEB1\0' or version!=1 or profile not in (1,2) or count!=4 or head!=128 or any(b[72:128]):
        raise ValueError('invalid bundle header')
    expected=((0,0x11c0000),(0x11c0000,0x230000),(0x1400000,C_LEN),(0x1800000,PMM_LEN))
    sections=[]; pos=head
    for i,(offset,length) in enumerate(expected):
        actual_off,actual_len,crc=struct.unpack_from('<III',b,24+i*12)
        if (actual_off,actual_len)!=(offset,length): raise ValueError('wrong section mapping')
        data=b[pos:pos+length]
        if len(data)!=length or zlib.crc32(data)!=crc: raise ValueError('section length or CRC mismatch')
        sections.append(data);pos+=length
    if pos!=len(b): raise ValueError('trailing bundle bytes')
    return profile,sections

def make_header(profile,core_sha,ext_sha):
    prefix=struct.pack('<8sIIII32s32s',MAGIC,1,profile,C_LEN,PMM_LEN,core_sha,ext_sha)
    h=prefix.ljust(HEADER-4,b'\0')
    return h+struct.pack('<I',zlib.crc32(h))

def parse_save(path):
    return _parse_save_bytes(path.read_bytes())

def _parse_save_bytes(data):
    if len(data)!=SIZE: raise ValueError('wrong save image size')
    h=data[:HEADER]
    if zlib.crc32(h[:-4])!=struct.unpack_from('<I',h,HEADER-4)[0]: raise ValueError('header CRC mismatch')
    magic,version,profile,csize,psize,core,ext=struct.unpack_from('<8sIIII32s32s',h)
    if magic!=MAGIC or version!=1 or profile not in (1,2) or csize!=C_LEN or psize!=PMM_LEN or any(h[88:-4]): raise ValueError('invalid save header')
    return data,profile,core,ext


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def write_new_files(files):
    """Reserve all outputs exclusively before writing, undoing only our own files."""
    opened = []
    try:
        for path, data in files:
            stream = path.open('xb')
            opened.append((path, stream))
        for (_, stream), (_, data) in zip(opened, files):
            stream.write(data)
            stream.close()
    except Exception:
        for path, stream in opened:
            stream.close()
            path.unlink()
        raise


def split_raw(save, cdrive, pmm, manifest):
    data, profile, core, ext = parse_save(save)
    cbytes = data[HEADER:HEADER + C_LEN]
    pbytes = data[HEADER + C_LEN:]
    metadata = {
        'format': 'ngage-raw-persistence-v1',
        'source': {'path': str(save.resolve()), 'bytes': len(data),
                   'sha256': sha256(data)},
        'profile': profile, 'core_sha256': core.hex(),
        'extension_sha256': ext.hex(),
        'header_base64': base64.b64encode(data[:HEADER]).decode('ascii'),
        'header_sha256': sha256(data[:HEADER]),
        'images': {
            'cdrive': {'file': cdrive.name, 'bytes': C_LEN, 'offset': HEADER,
                       'sha256': sha256(cbytes)},
            'pmm': {'file': pmm.name, 'bytes': PMM_LEN, 'offset': HEADER + C_LEN,
                    'sha256': sha256(pbytes)}},
        'layout': 'raw bytes; no VHD container/footer; NEM-4 only',
    }
    write_new_files([(cdrive, cbytes), (pmm, pbytes),
                     (manifest, (json.dumps(metadata, indent=2) + '\n').encode())])
    return metadata


def join_raw(manifest, cdrive, pmm, output):
    metadata = json.loads(manifest.read_text())
    if not isinstance(metadata, dict) or metadata.get('format') != 'ngage-raw-persistence-v1':
        raise ValueError('unsupported raw manifest')
    try:
        header = base64.b64decode(metadata['header_base64'], validate=True)
        cbytes, pbytes = cdrive.read_bytes(), pmm.read_bytes()
        if len(header) != HEADER or sha256(header) != metadata['header_sha256']:
            raise ValueError('manifest header length/hash mismatch')
        # Reuse the NGA parser, including reserved-byte, profile and CRC checks.
        if len(cbytes) != C_LEN or len(pbytes) != PMM_LEN:
            raise ValueError('raw images must be exactly 4 MiB and 64 KiB')
        if (metadata['profile'], metadata['core_sha256'], metadata['extension_sha256']) != (
                struct.unpack_from('<I', header, 12)[0], header[24:56].hex(), header[56:88].hex()):
            raise ValueError('manifest firmware identity mismatch')
        for name, length, offset in [('cdrive', C_LEN, HEADER),
                                     ('pmm', PMM_LEN, HEADER + C_LEN)]:
            image = metadata['images'][name]
            if image['bytes'] != length or image['offset'] != offset:
                raise ValueError('manifest image geometry mismatch')
        original = metadata['source']
        for digest in [original['sha256'], metadata['images']['cdrive']['sha256'],
                       metadata['images']['pmm']['sha256']]:
            if not isinstance(digest, str) or len(digest) != 64 or any(
                    ch not in '0123456789abcdef' for ch in digest):
                raise ValueError('invalid manifest SHA-256')
        if original['bytes'] != SIZE:
            raise ValueError('manifest source length mismatch')
        # The header carries firmware metadata, not mutable-payload checksums.
        # Unchanged payloads must reconstruct the original source hash exactly.
        data = header + cbytes + pbytes
        if (sha256(cbytes) == metadata['images']['cdrive']['sha256'] and
                sha256(pbytes) == metadata['images']['pmm']['sha256'] and
                sha256(data) != original['sha256']):
            raise ValueError('manifest original source hash mismatch')
        _parse_save_bytes(data)
    except (KeyError, TypeError) as exc:
        raise ValueError('incomplete raw manifest') from exc
    write_new_files([(output, data)])
    return sha256(data)

def main():
    ap=argparse.ArgumentParser(description=__doc__);sub=ap.add_subparsers(dest='cmd',required=True)
    create=sub.add_parser('create');create.add_argument('bundle',type=Path);create.add_argument('output',type=Path)
    info=sub.add_parser('inspect');info.add_argument('save',type=Path);info.add_argument('--bundle',type=Path)
    split=sub.add_parser('split-raw', help='extract an NGA into raw C/PMM and a rollback manifest')
    split.add_argument('save',type=Path)
    split.add_argument('--cdrive',type=Path,required=True)
    split.add_argument('--pmm',type=Path,required=True)
    split.add_argument('--manifest',type=Path,required=True)
    join=sub.add_parser('join-raw', help='rebuild NGA with original header and current raw payloads')
    join.add_argument('manifest',type=Path)
    join.add_argument('--cdrive',type=Path,required=True)
    join.add_argument('--pmm',type=Path,required=True)
    join.add_argument('--output',type=Path,required=True)
    args=ap.parse_args()
    try:
        if args.cmd=='split-raw':
            split_raw(args.save,args.cdrive,args.pmm,args.manifest)
            print('Created raw C:/PMM images and rollback manifest')
        elif args.cmd=='join-raw':
            digest=join_raw(args.manifest,args.cdrive,args.pmm,args.output)
            print('Created NGA:',args.output,'sha256:',digest)
        elif args.cmd=='create':
            profile,parts=parse_bundle(args.bundle)
            header=make_header(profile,hashlib.sha256(parts[0]).digest(),hashlib.sha256(parts[1]).digest())
            with args.output.open('xb') as f:f.write(header);f.write(parts[2]);f.write(parts[3])
            print('Created new working save:',args.output)
        else:
            data,profile,core,ext=parse_save(args.save)
            if args.bundle:
                bp,parts=parse_bundle(args.bundle)
                if (profile,core,ext)!=(bp,hashlib.sha256(parts[0]).digest(),hashlib.sha256(parts[1]).digest()):raise ValueError('save belongs to a different firmware/profile')
            print(json.dumps({'format':'NGSAVE1 provisional','profile':profile,'bytes':len(data),'core_sha256':core.hex(),'extension_sha256':ext.hex(),'cdrive_sha256':hashlib.sha256(data[HEADER:HEADER+C_LEN]).hexdigest(),'pmm_sha256':hashlib.sha256(data[HEADER+C_LEN:]).hexdigest(),'fpga_persistence':'simulation-tested; hardware not verified'},indent=2))
    except (OSError,ValueError) as e:raise SystemExit(str(e))
if __name__=='__main__':main()
