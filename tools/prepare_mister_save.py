#!/usr/bin/env python3
"""Create or inspect a provisional N-Gage MiSTer working save image.

The image has a 512-byte header followed by raw C: (4 MiB) and PMM (64 KiB).
It is separate from the immutable bundle. HDL save/restore is simulation-tested;
real MiSTer persistence and power-cycle recovery remain unverified.
"""
import argparse
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
    data=path.read_bytes()
    if len(data)!=SIZE: raise ValueError('wrong save image size')
    h=data[:HEADER]
    if zlib.crc32(h[:-4])!=struct.unpack_from('<I',h,HEADER-4)[0]: raise ValueError('header CRC mismatch')
    magic,version,profile,csize,psize,core,ext=struct.unpack_from('<8sIIII32s32s',h)
    if magic!=MAGIC or version!=1 or profile not in (1,2) or csize!=C_LEN or psize!=PMM_LEN or any(h[88:-4]): raise ValueError('invalid save header')
    return data,profile,core,ext

def main():
    ap=argparse.ArgumentParser(description=__doc__);sub=ap.add_subparsers(dest='cmd',required=True)
    create=sub.add_parser('create');create.add_argument('bundle',type=Path);create.add_argument('output',type=Path)
    info=sub.add_parser('inspect');info.add_argument('save',type=Path);info.add_argument('--bundle',type=Path)
    args=ap.parse_args()
    try:
        if args.cmd=='create':
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
