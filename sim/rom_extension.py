#!/usr/bin/env python3
"""Build an explicitly reconstructed NEM-4 extension, preserving all source bytes."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from inspect_boot import EXPECTED
from inventory_firmware import inspect_image, rom_tree

ROOT = Path(__file__).resolve().parents[1]
ROOT_SHA = '2fb73cd7e2269fcb2a11733061a84a78ed3e61803be7021a9672d594bd5378b4'
DEFAULT = ROOT/'build/firmware/nem4-extension/extension.bin'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def validate(core_path,tail_path):
    core = core_path.read_bytes()
    tail = tail_path.read_bytes()
    manifest = json.loads(tail_path.with_suffix('.json').read_text())
    if sha(core) != EXPECTED or manifest.get('core_sha256') != EXPECTED:
        raise ValueError('extension requires the inspected original N-Gage 4.03 core')
    if manifest.get('format') != 'ngage-reconstructed-extension-v1' or not manifest.get('reconstructed'):
        raise ValueError('extension lacks its explicit reconstruction manifest')
    if manifest.get('tail_sha256') != sha(tail) or len(tail) != manifest['tail_bytes']:
        raise ValueError('extension payload differs from its manifest')
    if manifest['virtual_start'] != 0x50000000+len(core):
        raise ValueError('extension does not follow the original core')
    if manifest['virtual_end'] != manifest['virtual_start']+len(tail):
        raise ValueError('extension range/length mismatch')
    if manifest['root_sha256'] != ROOT_SHA:
        raise ValueError('extension has an unrecognized recovered ROOT source')
    start = manifest['root_virtual_start']-manifest['virtual_start']
    length = manifest['root_bytes']
    if not 0 <= start <= len(tail)-length or sha(tail[start:start+length]) != ROOT_SHA:
        raise ValueError('recovered ROOT bytes have changed')
    return manifest


def build(output):
    core_path = ROOT/'firmware/SYM.ROM'
    bundle_rom = ROOT/'firmware/Nokia N-Gage/Data/roms/NEM-4/SYM.ROM'
    info = inspect_image(bundle_rom)
    core = core_path.read_bytes()
    if sha(core) != EXPECTED or info['sha256'] != EXPECTED:
        raise ValueError('only the inspected NEM-4 image can be reconstructed')
    root_path = ROOT/info['root_dump']['path']
    recovered = root_path.read_bytes()
    if sha(recovered) != ROOT_SHA:
        raise ValueError('recovered ROOT source differs from the inspected snapshot')
    begin = 0x50000000+len(core)
    root_base = info['root_dump']['inferred_virtual_start']
    root_end = root_base+len(recovered)
    # Cover only selected type-1 ROM banks. Their remaining padding is an
    # explicit erased/no-further-image assumption, not writable user flash.
    total = sum(struct.unpack_from('<I',core,0x830+8+16*i+4)[0]
                for i in range(struct.unpack_from('<I',core,0x830)[0])
                if struct.unpack_from('<I',core,0x830+8+16*i+8)[0]&31 == 1)
    finish = 0x50000000+total
    if not begin < root_base < root_end <= finish:
        raise ValueError('recovered ROOT does not fit the selected ROM banks')
    tail = bytearray(b'\xff'*(finish-begin))
    spans = []
    def place(address,payload,kind,label):
        end = address+len(payload)
        if not begin <= address <= end <= finish:
            raise ValueError(f'span outside tail: {label}')
        if any(address < item['end'] and item['address'] < end for item in spans):
            raise ValueError(f'overlapping reconstructed spans: {label}')
        tail[address-begin:end-begin] = payload
        spans.append(dict(address=address,end=end,bytes=len(payload),kind=kind,label=label,sha256=sha(payload)))
    place(root_base,recovered,'recovered','unaltered ROOT snapshot')
    nodes = {'':dict(name='',children={},files={},address=root_base)}
    def directory(path):
        current = ''
        for name in Path(path).parts:
            if name == '.':
                continue
            parent = current
            current = f'{current}/{name.lower()}' if current else name.lower()
            if current not in nodes:
                nodes[current] = dict(name=name,children={},files={})
                nodes[parent]['children'][name.lower()] = current
        return current
    for entry in info['header']['directories']:
        directory(entry['path'])
    for entry in info['rom_files']:
        parent = directory(str(Path(entry['path']).parent))
        name = Path(entry['path']).name
        nodes[parent]['files'][name.lower()] = dict(name=name,bytes=entry['bytes'],address=entry['address'],attributes=entry['attributes'])
    for entry in info['extra_files']:
        if entry.get('root_dump_offset') is None:
            raise ValueError('an extra file has no recovered backing')
        parent = directory(str(Path(entry['path']).parent))
        name = Path(entry['path']).name
        nodes[parent]['files'][name.lower()] = dict(name=name,bytes=entry['bytes'],address=root_base+entry['root_dump_offset'],attributes=1)
    # The recovered root directory itself is preserved. Rebuild the two
    # missing child directories at the addresses it already names.
    count = struct.unpack_from('<I',recovered)[0]
    cursor = 4
    fixed = {}
    while cursor < count+4:
        _,address,attributes,n = struct.unpack_from('<IIBB',recovered,cursor)
        name = recovered[cursor+10:cursor+10+2*n].decode('utf-16-le')
        if not attributes&16 or name.lower() not in nodes['']['children']:
            raise ValueError('unrecognized recovered top directory')
        fixed[name.lower()] = address
        nodes[name.lower()]['address'] = address
        cursor = (cursor+10+2*n+3)&~3
    if set(fixed) != set(nodes['']['children']):
        raise ValueError('reconstructed tree disagrees with recovered root children')
    def records(node):
        entries = [dict(name=nodes[key]['name'],bytes=0,address=nodes[key].get('address',0),attributes=16)
                   for key in node['children'].values()]
        entries += list(node['files'].values())
        return sorted(entries,key=lambda entry:entry['name'].lower())
    def serialize(node):
        payload = bytearray()
        for entry in records(node):
            name = entry['name'].encode('utf-16-le')
            payload += struct.pack('<IIBB',entry['bytes'],entry['address'],entry['attributes'],len(name)//2)+name
            payload += b'\x00'*((-len(payload))%4)
        # EKA1 directories in the supplied ROM use UTF-16 records and no
        # EKA2 TRomDirSortInfo trailer. Do not import the later format.
        return struct.pack('<I',len(payload))+payload
    cursor = begin+0x1000
    low_fixed = min(fixed.values())
    for key,node in sorted(nodes.items()):
        if key == '' or key in fixed:
            continue
        node['address'] = cursor
        cursor += (len(serialize(node))+3)&~3
    if cursor > low_fixed:
        raise ValueError('rebuilt directory prefix exceeds available gap')
    for key,node in nodes.items():
        if key:
            place(node['address'],serialize(node),'synthesized-directory',key)
    root_list = begin+0x80
    hardware = info['header']['roots'][0]['hardware']
    place(root_list,struct.pack('<III',1,hardware,root_base),'synthesized-root-list','one combined hardware root')
    header = bytearray(128)
    version,time_lo,time_hi = struct.unpack_from('<III',core,0x80)
    fields = {0:version,4:time_lo,8:time_hi,0xc:begin,0x10:root_end-begin,0x14:root_list,
              0x18:0,0x1c:version,0x20:time_lo,0x24:time_hi,0x28:struct.unpack_from('<I',core,0xa8)[0],
              0x2c:0,0x30:root_end-begin,0x34:root_end-begin}
    for offset,value in fields.items():
        struct.pack_into('<I',header,offset,value)
    place(begin,header,'synthesized-extension-header','EKA1 bootstrap-observed layout')
    # Validate the entire merged filesystem in a throwaway in-memory view.
    # The original core/header are not patched in the emitted tail artifact.
    verification = bytearray(core)+tail
    struct.pack_into('<I',verification,0x94,root_list)
    _,entries = rom_tree(verification)
    expected = {entry['path'].lower():entry for entry in info['rom_files']}
    expected.update({entry['path'].lower():entry for entry in info['extra_files']})
    if len(entries) != len(expected):
        raise ValueError('merged filesystem file count differs')
    for entry in entries:
        source = expected[entry['path'].lower()]
        if entry['sha256'] != source['sha256'] or entry['bytes'] != source['bytes']:
            raise ValueError(f'reconstructed file differs: {entry["path"]}')
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_bytes(tail)
    manifest = dict(format='ngage-reconstructed-extension-v1',reconstructed=True,core_sha256=EXPECTED,
                    root_sha256=ROOT_SHA,root_bytes=len(recovered),root_virtual_start=root_base,
                    virtual_start=begin,virtual_end=finish,tail_bytes=len(tail),tail_sha256=sha(tail),
                    extension_image_end=root_end,root_directory_list=root_list,root_directory=root_base,
                    files_verified=len(entries),directories=len(nodes),spans=sorted(spans,key=lambda span:span['address']),
                    erased_padding_assumption=True,padding_byte=255,physical_mapping_verified=False,
                    header_authentic=False,directories_authentic=False,root_bytes_unchanged=True,
                    assumptions=['Extension header starts at the first post-core candidate.',
                                 'Extension version/time mirror the core; checksum is synthesized as zero.',
                                 'Missing UTF-16 EKA1 directory records are rebuilt from known paths and payload addresses.',
                                 'All uncovered bytes in the selected ROM-bank tail are assumed erased; writable/type-3 regions are excluded.'],
                    builder_sha256=sha(Path(__file__).read_bytes()))
    output.with_suffix('.json').write_text(json.dumps(manifest,indent=2)+'\n')
    validate(core_path,output)
    print(f'Built {len(tail)}-byte reconstructed tail; verified all {len(entries)} merged files.')
    print(f'ROOT preserved at 0x{root_base:08x}; synthetic header at 0x{begin:08x}.')
    print(f'Manifest: {output.with_suffix(".json")}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=DEFAULT)
    args = parser.parse_args()
    build(args.output.resolve())


if __name__=='__main__':
    try:
        main()
    except (OSError,ValueError,KeyError,struct.error) as error:
        raise SystemExit(str(error))
