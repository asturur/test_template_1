#!/usr/bin/env python3
"""Inventory local ROMs and verify unpacked Z: files without executing firmware."""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import re
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ROM_MODULE_UIDS = {0x10000079,0x1000007a}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def text_file(path):
    data = path.read_bytes()
    encoding = 'utf-16' if data.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8'
    return data.decode(encoding,errors='replace')


def files_under(path):
    return sorted(p for p in path.rglob('*') if p.is_file() and p.name != '.DS_Store')


def rom_tree(data):
    base,size,root_list = struct.unpack_from('<III',data,0x8c)
    def u32(at):
        if not 0 <= at <= len(data)-4:
            raise ValueError(f'ROM word outside file at {at:x}')
        return struct.unpack_from('<I',data,at)[0]
    root_offset = root_list-base
    count = u32(root_offset)
    if not 0 < count <= 32:
        raise ValueError('invalid root-directory count')
    roots,entries = [],[]
    directories = set()
    directory_entries = []
    def walk(address,path,ancestors):
        at = address-base
        if address in ancestors:
            raise ValueError('directory cycle')
        directories.add(address)
        directory_entries.append(dict(path=path,address=address))
        end = at+4+u32(at)
        if not at+4 <= end <= len(data):
            raise ValueError('directory outside ROM')
        cursor = at+4
        while cursor < end:
            if cursor+10 > end:
                raise ValueError('truncated directory entry')
            length,pointer,attributes,name_length = struct.unpack_from('<IIBB',data,cursor)
            name_end = cursor+10+name_length*2
            if name_end > end:
                raise ValueError('directory name outside bounds')
            name = data[cursor+10:name_end].decode('utf-16-le')
            full = f'{path}/{name}' if path else name
            cursor = (name_end+3)&~3
            if attributes&16:
                walk(pointer,full,ancestors|{address})
            else:
                offset = pointer-base
                if not 0 <= offset <= len(data) or offset+length > len(data):
                    raise ValueError(f'file outside ROM: {full}')
                entries.append(dict(path=full,bytes=length,address=pointer,file_offset=offset,
                                    attributes=attributes,sha256=digest(data[offset:offset+length])))
    for index in range(count):
        hardware,address = struct.unpack_from('<II',data,root_offset+4+8*index)
        roots.append(dict(hardware=hardware,address=address))
        walk(address,'',set())
    return dict(base=base,declared_bytes=size,root_list=root_list,roots=roots,
                directory_count=len(directories),directories=directory_entries),entries


def entry_pointer(data,address,base):
    if not address:
        return None
    offset = address-base
    if not 0 <= offset <= len(data)-10:
        return dict(address=address,contained=False)
    size,pointer,attributes,count = struct.unpack_from('<IIBB',data,offset)
    end = offset+10+2*count
    if end > len(data):
        raise ValueError('entry pointer name outside image')
    return dict(address=address,bytes=size,payload_address=pointer,attributes=attributes,
                name=data[offset+10:end].decode('utf-16-le'),contained=True)


def module_info(data,entry):
    offset,size = entry['file_offset'],entry['bytes']
    if size < 100 or struct.unpack_from('<I',data,offset)[0] not in ROM_MODULE_UIDS:
        return None
    header = struct.unpack_from('<18I',data,offset)
    code,size_code = header[5],header[7]
    base = entry['address']-offset
    code_offset = code-base
    if not 0 <= code_offset <= len(data) or size_code > len(data)-code_offset:
        raise ValueError('module code outside ROM')
    code_end = min(code_offset+size_code,offset+size)
    if code_end < code_offset:
        raise ValueError("module code begins beyond its directory payload")
    block = data[code_offset:code_end]
    literals = []
    for at in range(0,len(block)-3,4):
        value = struct.unpack_from('<I',block,at)[0]
        if 0x58000000 <= value < 0x60000000 or 0x0c000000 <= value < 0x0c200000:
            literals.append(dict(address=code+at,value=value))
    return dict(path=entry['path'],address=entry['address'],bytes=size,
                uid1=header[0],uid2=header[1],uid3=header[2],entry_point=header[4],
                code_address=code,declared_code_bytes=size_code,scanned_code_bytes=len(block),sha256=entry['sha256'],
                candidate_mmio_literals=literals,
                note='Literal values are leads; control-flow/device semantics are not established by a numeric match.')


def inspect_image(rom):
    data = rom.read_bytes()
    header,entries = rom_tree(data)
    base = header['base']
    result = dict(path=str(rom.relative_to(ROOT)),bytes=len(data),sha256=digest(data),
                  header=header,declared_size_matches_file=header['declared_bytes']==len(data),
                  version_time_words=list(struct.unpack_from('<3I',data,0x80)),
                  header_entry_pointers={f'0x{at:x}':entry_pointer(data,struct.unpack_from('<I',data,at)[0],base)
                                         for at in (0xa0,0xa4,0xd0,0xd4)},
                  rom_files=entries)
    if rom.parent.parent.name.lower() != 'roms':
        result['role'] = 'standalone working ROM copy'
        return result
    dataset = rom.parents[2]
    drive_root = dataset/'drives/z'
    tree = next((p for p in drive_root.iterdir() if p.name.lower()==rom.parent.name.lower()),None)
    if tree is None:
        raise ValueError(f'no matching unpacked Z: tree for {rom}')
    local = {p.relative_to(tree).as_posix().lower():p for p in files_under(tree)}
    entry_names = {e['path'].lower() for e in entries}
    comparisons = collections.Counter()
    for entry in entries:
        file = local.get(entry['path'].lower())
        entry['unpacked_match'] = file is not None and digest(file.read_bytes())==entry['sha256']
        comparisons['exact_matches' if entry['unpacked_match'] else 'missing' if file is None else 'different'] += 1
    extras = []
    for key,file in local.items():
        if key not in entry_names:
            payload = file.read_bytes()
            extras.append(dict(path=file.relative_to(tree).as_posix(),bytes=len(payload),sha256=digest(payload),
                               ida_database=payload.startswith(b'IDA1')))
    result.update(role='ROM plus unpacked Z: tree',unpacked_tree=str(tree.relative_to(ROOT)),
                  unpacked_files=len(local),rom_file_count=len(entries),file_comparison=dict(comparisons),
                  extra_files=extras)
    version = next((p for key,p in local.items() if key.endswith('/versions/sw.txt')),None)
    result['software_version_text'] = text_file(version) if version else None
    modules = ('ekern.exe','lcd.ldd','medint.pdd','hal.dll','midpinstaller.dll','midprecog.mdl')
    result['selected_modules'] = [module_info(data,entry) for entry in entries
                                  if Path(entry['path']).name.lower() in modules]
    result['selected_modules'] = [module for module in result['selected_modules'] if module]
    result['midp_files'] = [entry['path'] for entry in entries
                            if re.search(r'(?i)midp|j2me|cldc|jvm|java',entry['path'])]
    result['symbols'] = [extra for extra in extras if extra['ida_database']]
    for dump in sorted(rom.parent.glob('*.dmp')):
        payload = dump.read_bytes()
        first = data.find(payload[:64]) if len(payload)>=64 else -1
        match = first>=0 and data[first:first+len(payload)]==payload
        report = dict(path=str(dump.relative_to(ROOT)),bytes=len(payload),sha256=digest(payload),
                      first_64_bytes_match_offset=first if first>=0 else None,
                      exact_rom_slice=match,rom_slice_offset=first if match else None)
        if dump.name.startswith('ROOT'):
            anchors = []
            for extra in extras:
                if extra['ida_database']:
                    continue
                file = local[extra['path'].lower()]
                contents = file.read_bytes()
                at = payload.find(contents) if contents else 0
                extra['root_dump_offset'] = at if at>=0 else None
                if file.suffix.lower()=='.dll' and at>=0 and len(contents)>=100:
                    uid1 = struct.unpack_from('<I',contents)[0]
                    if uid1 in ROM_MODULE_UIDS:
                        code_address = struct.unpack_from('<I',contents,20)[0]
                        module_base = code_address-100
                        anchors.append(dict(path=extra['path'],module_address=module_base,
                                            root_offset=at,implied_root_address=module_base-at))
            origins = {a['implied_root_address'] for a in anchors}
            report.update(extra_file_exact_matches=sum(e.get('root_dump_offset') is not None for e in extras),
                          extra_file_count=len(extras),origin_anchors=anchors)
            if len(anchors)>=2 and len(origins)==1:
                origin = origins.pop()
                report.update(inferred_virtual_start=origin,inferred_virtual_end=origin+len(payload),
                              origin_method='Independent XIP DLL code addresses minus 100-byte EKA1 module headers and their exact offsets in ROOT.')
            elif match:
                report.update(inferred_virtual_start=base+first,inferred_virtual_end=base+first+len(payload),
                              origin_method='Entire ROOT byte-identical to this interval of its own ROM.')
            result['root_dump'] = report
        elif dump.name.startswith('BOOT'):
            result['boot_dump'] = report
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory',type=Path,default=ROOT/'firmware')
    parser.add_argument('--output',type=Path,default=ROOT/'build/firmware/inventory.json')
    args = parser.parse_args()
    directory = args.directory.resolve()
    images = [inspect_image(path) for path in sorted(directory.rglob('SYM.ROM'))]
    archives = []
    for path in sorted(directory.glob('*.zip')):
        with zipfile.ZipFile(path) as archive:
            archives.append(dict(path=str(path.relative_to(ROOT)),bytes=path.stat().st_size,
                                 members=len(archive.infolist()),sample_names=archive.namelist()[:5]))
    report = dict(images=images,archives=archives,inputs_modified=False,firmware_executed=False,
                  notes=['ROM filesystem parser follows the retained EKA2L1 ROM entry layout.',
                         'ROOT is a virtual snapshot, not an automatically complete physical chip image.',
                         'RH-4 is a bundle label; the developer version text identifies an RH-29 software variant.'])
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    for image in images:
        print(image['path'],image['bytes'],'bytes',image.get('software_version_text','working copy'))
        if 'file_comparison' in image:
            print(' ROM files:',image['rom_file_count'],'unpacked matches:',image['file_comparison'],
                  'extra files:',len(image['extra_files']),'IDA databases:',len(image['symbols']))
            root = image.get('root_dump',{})
            print(' ROOT contains extra files:',root.get('extra_file_exact_matches'),
                  'virtual range:',hex(root['inferred_virtual_start'])+'..'+hex(root['inferred_virtual_end']) if 'inferred_virtual_start' in root else 'unresolved')
    print('Report:',args.output)


if __name__=='__main__':
    try:
        main()
    except (OSError,ValueError,struct.error,zipfile.BadZipFile) as error:
        raise SystemExit(str(error))
