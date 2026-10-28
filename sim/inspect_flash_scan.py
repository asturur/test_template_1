#!/usr/bin/env python3
"""Explain the saved N-Gage 4.03 post-ROM scan without rerunning either CPU."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import struct

from inspect_boot import EXPECTED

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inspect(rom, trace):
    firmware = rom.read_bytes()
    result_path = trace.with_name('result.json')
    result = json.loads(result_path.read_text())
    if digest(rom) != EXPECTED or result.get('rom_sha256') != EXPECTED:
        raise ValueError('this analysis requires the inspected N-Gage 4.03 ROM and its trace')
    if result.get('pc') != 0x1ea4 or result.get('operation') != 'read':
        raise ValueError('expected the saved software stop at the first candidate-header read, PC 0x1ea4')
    watched = (0xe18,0xe9c,0xecc,0x1e2c,0x1e30,0x1e3c,0x1e4c,0x1e58,0x1e7c,0x1e84,0x1ea0)
    events = {}
    with trace.open() as stream:
        for row in csv.DictReader(stream, delimiter='\t'):
            pc = int(row['pc'],16)
            if pc in watched:
                events[pc] = row
    if set(events) != set(watched):
        raise ValueError('trace lacks one or more required caller/scanner observations')
    def value(pc):
        return int(events[pc]['data'],16)
    base, size = struct.unpack_from('<II',firmware,0x8c)
    if value(0xe18) != base or value(0xe9c) != size:
        raise ValueError('observed ROM mapping arguments disagree with the local image header')
    next_virtual = value(0x1e3c)
    if value(0xecc) != next_virtual or next_virtual != base + size:
        raise ValueError('scanner is not at the recorded end-of-core-ROM boundary')
    pointer = value(0x1e30)
    if pointer != 0x80 or value(0x1ea0) != struct.unpack_from('<I',firmware,pointer)[0]:
        raise ValueError('expected the observed core header version/time comparison at physical 0x80')
    signature = firmware[pointer:pointer+12]
    candidate = result['blocked_address'] - 0x1c
    occurrences = []
    cursor = 0
    while True:
        at = firmware.find(signature,cursor)
        if at < 0:
            break
        occurrences.append(at)
        cursor = at+1
    aligned = [at-0x1c for at in occurrences if at >= 0x1c and (at-0x1c)%0x10000 == 0]
    return dict(
        firmware=str(rom),rom_sha256=EXPECTED,trace=str(trace),trace_sha256=digest(trace),
        source_result=str(result_path),board_model_sources=result.get('bridge',{}).get('sources',{}),
        core_virtual_base=base,core_bytes=size,next_virtual=next_virtual,
        candidate_physical_base=candidate,requested_address=result['blocked_address'],
        bank_entry_pointer=int(events[0x1e4c]['address'],16),
        bank_physical_base=value(0x1e7c),bank_bytes=value(0x1e84),bank_flags=value(0x1e58),
        expected_header=dict(core_pointer=pointer,words=list(struct.unpack('<3I',signature)),
                             bytes=signature.hex(),candidate_header_offset=0x1c,
                             next_candidate_stride=0x10000),
        pattern_occurrences=occurrences,aligned_candidate_headers_with_pattern=aligned,
        evidence={f'0x{pc:04x}':events[pc] for pc in watched},
        interpretation='The core ROM has been mapped; the scanner probes subsequent candidate headers. An optional extension-image search is inferred from the control flow and version/time/base comparisons.',
        limitations='The failed read has no return value. Expected comparison words are not observed flash contents. The physical map and erased/occupied tail remain unverified.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rom',type=Path,default=ROOT/'firmware/SYM.ROM')
    parser.add_argument('--trace',type=Path,default=ROOT/'build/oracle/amd16-ideal-clocks-lcd-probe/bus.tsv')
    parser.add_argument('--output',type=Path,default=ROOT/'build/sim/flash-scan-analysis.json')
    args = parser.parse_args()
    report = inspect(args.rom.resolve(),args.trace.resolve())
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(f"Core virtual end: 0x{report['next_virtual']:08x}")
    print(f"Next physical candidate: 0x{report['candidate_physical_base']:08x}; read 0x{report['requested_address']:08x}")
    print('Comparison words:',','.join(f'{word:08x}' for word in report['expected_header']['words']))
    print('Matching 64-KiB-aligned candidate headers in supplied file:',len(report['aligned_candidate_headers_with_pattern']))
    print(f'Report: {args.output}')


if __name__ == '__main__':
    try:
        main()
    except (OSError,ValueError,KeyError) as error:
        raise SystemExit(str(error))
