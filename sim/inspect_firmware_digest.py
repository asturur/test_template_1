#!/usr/bin/env python3
"""Read-only proof of the NEM-4 embedded MD5 mismatch and FPGA result."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import struct

from inspect_boot import EXPECTED

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RUN = ROOT/'build/sim/runs/firmware-amd16-latency0-ideal-clocks-lcd-probe-extension-boot-io-adc6-200'


def inspect(rom, runs):
    payload = rom.read_bytes()
    if hashlib.sha256(payload).hexdigest() != EXPECTED:
        raise ValueError('fixed descriptor offsets apply only to the pinned NEM-4 core')
    start,end = struct.unpack_from('<2I',payload,0x8f18)
    assert (start,end)==(0x50009000,0x511b4fff)
    first,last = start-0x50000000,end-0x50000000+1
    expected = payload[0x8f20:0x8f30].hex()
    computed = hashlib.md5(payload[first:last]).hexdigest()
    hardware = []
    for directory in runs:
        result = json.loads((directory/'result.json').read_text())
        if result['rom_sha256'] != EXPECTED:
            raise ValueError('HDL run uses a different core image')
        recovered = {}
        trace = directory/'memory-tail.tsv'
        with trace.open() as stream:
            for row in csv.DictReader(stream,delimiter='\t'):
                address = int(row['address'],16)
                if row['operation'] != 'WRITE' or not 0x0c004748 <= address < 0x0c004758:
                    continue
                select,data = int(row['byte_enable'],16),int(row['data'],16)
                for lane in range(4):
                    if select&(1<<lane):
                        recovered[address+lane] = data>>(8*lane)&255
        if len(recovered)!=16:
            raise ValueError('saved HDL tail does not contain the complete digest output')
        digest = bytes(recovered[0x0c004748+i] for i in range(16)).hex()
        hardware.append(dict(run=str(directory),cycles=result['cycles'],status=result['status'],
                             md5=digest,matches_independent_hashlib=digest==computed,
                             result_sha256=hashlib.sha256((directory/'result.json').read_bytes()).hexdigest(),
                             trace_sha256=hashlib.sha256(trace.read_bytes()).hexdigest()))
    return dict(core_sha256=EXPECTED,descriptor_file_offset='0x8f18',
                checked_virtual_start=hex(start),checked_virtual_end_inclusive=hex(end),
                checked_file_start=hex(first),checked_file_end_exclusive=hex(last),
                checked_bytes=last-first,embedded_expected_md5=expected,
                supplied_bytes_md5=computed,matches_embedded_digest=expected==computed,
                extension_in_checked_range=False,original_inputs_modified=False,
                rejection_call='0x500032e8',rejection_loop='0x50003290',hardware=hardware,
                conclusion='Original core bytes disagree with their embedded digest; the separate extension is outside this range.',
                provenance_caveat='Cause of the differing logical dump is not authenticated; this is not proof of its original physical-flash content.')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rom',type=Path,default=ROOT/'firmware/SYM.ROM')
    parser.add_argument('--hdl',type=Path,action='append',help='HDL run folder containing result.json and memory-tail.tsv')
    parser.add_argument('--output',type=Path,default=ROOT/'build/sim/firmware-digest-analysis.json')
    args=parser.parse_args()
    report=inspect(args.rom,args.hdl or [DEFAULT_RUN])
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    print('Embedded expected:',report['embedded_expected_md5'])
    print('Supplied core MD5:',report['supplied_bytes_md5'])
    print('HDL digests agree:',all(row['matches_independent_hashlib'] for row in report['hardware']))
    print('Report:',args.output)


if __name__=='__main__':
    main()
