#!/usr/bin/env python3
"""Build a non-authentic digest-metadata-only NEM-4 simulator experiment."""
import hashlib
import json
import os
from pathlib import Path
import struct

from inspect_boot import EXPECTED
from rom_extension import validate as validate_extension

ROOT=Path(__file__).resolve().parents[1]
DEFAULT_ROOT=ROOT/'build/firmware/digest-probes'
BASE=0x50000000


def sha(data):
    return hashlib.sha256(data).hexdigest()


def build(core_path,tail_path,mode,output_root=DEFAULT_ROOT):
    if mode not in ('core','both'):
        raise ValueError('unknown digest probe mode')
    core=core_path.read_bytes()
    if sha(core)!=EXPECTED:
        raise ValueError('digest probe requires the original inspected NEM-4 core')
    extension=validate_extension(core_path,tail_path)
    tail=tail_path.read_bytes()
    combined=core+tail
    derived=bytearray(core)
    fields=[('core',0x8f18)] + ([('extension',0x8f00)] if mode=='both' else [])
    changes=[]
    for name,descriptor in fields:
        start,end=struct.unpack_from('<II',core,descriptor)
        lo,hi=start-BASE,end-BASE+1
        if not 0<=lo<hi<=len(combined):
            raise ValueError(f'{name} digest range is not fully backed')
        metadata=descriptor+8
        if metadata+16>lo and metadata<hi:
            raise ValueError(f'{name} digest field overlaps its checked range')
        before=core[metadata:metadata+16]
        after=hashlib.md5(combined[lo:hi]).digest()
        derived[metadata:metadata+16]=after
        changes.append(dict(name=name,descriptor_offset=descriptor,digest_offset=metadata,
            virtual_start=start,virtual_end_inclusive=end,before=before.hex(),after=after.hex()))
    allowed={i for item in changes for i in range(item['digest_offset'],item['digest_offset']+16)}
    changed=[i for i,(a,b) in enumerate(zip(core,derived)) if a!=b]
    if not set(changed)<=allowed:
        raise ValueError('unexpected probe changes outside selected metadata')
    directory=output_root/mode
    directory.mkdir(parents=True,exist_ok=True)
    path=directory/'SYM.ROM'
    manifest=dict(format='ngage-digest-metadata-probe-v1',mode=mode,experimental=True,
                  authenticity_verified=False,source_core_sha256=EXPECTED,
                  source_extension_sha256=extension['tail_sha256'],derived_sha256=sha(derived),
                  changed_byte_count=len(changed),changes=changes,
                  note='Only embedded expected digest fields are replaced; no firmware code or input files are changed.')
    # Unique project-local temporary names keep concurrent generators safe.
    for target,data in ((path,bytes(derived)),(directory/'manifest.json',(json.dumps(manifest,indent=2)+'\n').encode())):
        if not target.exists() or target.read_bytes()!=data:
            temp=directory/f'.{target.name}.{os.getpid()}.tmp'
            temp.write_bytes(data)
            os.replace(temp,target)
    return path,manifest


def main():
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--core',type=Path,default=ROOT/'firmware/SYM.ROM')
    parser.add_argument('--tail',type=Path,default=ROOT/'build/firmware/nem4-extension/extension.bin')
    parser.add_argument('--mode',choices=('core','both'),required=True)
    args=parser.parse_args()
    path,manifest=build(args.core,args.tail,args.mode)
    print(f"Experimental {args.mode} digest metadata: {manifest['changed_byte_count']} changed bytes")
    print('Derived SHA-256:',manifest['derived_sha256'])
    print('Derived image:',path)


if __name__=='__main__':
    main()
