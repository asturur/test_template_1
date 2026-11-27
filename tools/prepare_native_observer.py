#!/usr/bin/env python3
"""Prepare the audited NEM-4 software observer for the existing DDR debugger.

Host only: writes a guarded remote script/manifest, never connects or applies it.
No Bluetooth/SIM/deadline/self-test substitutions. Recomputes the diagnostic
CPU-view MD5, retaining the firmware check. Reload undoes this instrumentation.
"""
import argparse
import hashlib
import inspect
import json
from pathlib import Path
import struct
import service_firmware
import ngage_runtime_bt as runtime
from build_virtual_sim import rules, decode16

ROOT = Path(__file__).resolve().parents[1]


def held_fresh(w):
    # Require physical Hold and saved Run off, completed restore, save off,
    # reset generation zero and no executed clocks or completed bus history.
    # One initial VA0 fetch is reset bookkeeping, not a cached hook page.
    flags = w[242]
    return (all(w[8+i] == 0 for i in (4, 10, 11))
            and w[13] <= 1 and w[8] == 0 and w[9] == 0
            and not (w[29] & 256) and w[30] & 1
            and w[6] == 0 and (flags & 7) == 0 and flags & (1 << 4)
            and flags & (1 << 25)
            and not flags & ((1 << 6) | (1 << 7) | (1 << 10) | (1 << 26)))


def prepare(out, slow_wait):
    raw = bytearray(b'\xff' * service_firmware.BACKING_SIZE)
    for kind, spec in service_firmware.PROFILES.items():
        source = ROOT / 'firmware/NEM-04 v.04.03 N-GAGE' / spec[0]
        service_firmware.apply(raw, service_firmware.parse(source.read_bytes(), kind), kind)
    if hashlib.sha256(raw).hexdigest() != runtime.ROM_SHA:
        raise ValueError('wrong original service backing')
    payload = (ROOT / 'build/firmware-overlays/exit-trace/trace.bin').read_bytes()
    records = runtime.exit_records(payload, slow_wait=slow_wait)
    view = bytearray(raw)
    rule = rules()
    for address in range(0xa000, 0x2b3000, 2):
        cipher = raw[address] | raw[address+1] << 8
        struct.pack_into('<H', view, address, decode16(cipher, address, rule))
    stock = bytes(view[0x8f20:0x8f30])
    if hashlib.md5(view[0x9000:0x11b5000]).digest() != stock:
        raise ValueError('original CPU-view MD5 does not match stock')
    for offset, old, new in records:
        if struct.unpack_from('<I', view, offset)[0] != old:
            raise ValueError('original observer word mismatch')
        struct.pack_into('<I', view, offset, new)
    digest = hashlib.md5(view[0x9000:0x11b5000]).digest()
    for i in range(4):
        offset = 0x8f20+i*4
        records.append((offset, struct.unpack_from('<I',raw,offset)[0],
                        struct.unpack_from('<I',digest,i*4)[0]))
    if any(offset in (0x8f18,0x8f1c) for offset, _, _ in records):
        raise ValueError('must retain original checksum bounds')
    for offset, old, new in records:
        if struct.unpack_from('<I',raw,offset)[0] != old:
            raise ValueError('raw old-word mismatch')
        struct.pack_into('<I',raw,offset,new)
    expected = hashlib.sha256(raw).hexdigest()
    report = dict(records=len(records), observer_sha256=runtime.EXIT_TRACE_SHA,
        original_rom_sha256=runtime.ROM_SHA, instrumented_rom_sha256=expected,
        stock_cpu_view_md5=stock.hex(), diagnostic_cpu_view_md5=digest.hex(),
        checksum_check_retained=True, slow_wait_trace=slow_wait,
        functional_startup_substitutions=False)
    script = 'import argparse,hashlib,json,mmap,os,struct,time\n'
    for name in ('BASE','SIZE','ROM_SIZE','ROM_SHA','EXIT_HOOKS'):
        script += name+'='+repr(getattr(runtime,name))+'\n'
    for function in (runtime.snapshot, held_fresh, runtime.validate_image, runtime.patch_image):
        script += '\n'+inspect.getsource(function)
    script += '\nrecords='+repr(sorted(records))+'\nreport='+repr(report)+'\n'
    script += '''
parser=argparse.ArgumentParser(description='Observation-only NEM-4 tracer; reload undoes it')
parser.add_argument('--apply',action='store_true')
args=parser.parse_args()
fd=os.open('/dev/mem',(os.O_RDWR if args.apply else os.O_RDONLY)|os.O_SYNC)
try:
 with mmap.mmap(fd,SIZE,access=mmap.ACCESS_WRITE if args.apply else mmap.ACCESS_READ,offset=BASE) as memory:
  validate_image(memory,records)
  first=snapshot(memory);report['fresh_held']=bool(held_fresh(first));report['applied']=False
  if args.apply:
   if not held_fresh(first):raise ValueError('fresh CPU Hold/save Off required; no writes made')
   deadline=time.monotonic()+3
   while True:
    time.sleep(.1);second=snapshot(memory)
    if not held_fresh(second):raise ValueError('freshness changed; no writes made')
    if first[2]!=second[2]:break
    if time.monotonic()>=deadline:raise ValueError('telemetry not advancing; no writes made')
   patch_image(memory,records)
   if hashlib.sha256(memory[:ROM_SIZE]).hexdigest()!=report['instrumented_rom_sha256']:
    raise ValueError('instrumented full-image verification failed')
   report['applied']=True
  print(json.dumps(report))
finally:os.close(fd)
'''
    out.mkdir(parents=True, exist_ok=True)
    (out/'observer.py').write_text(script)
    (out/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--slow-wait', action='store_true')
    args = parser.parse_args()
    try:
        print(json.dumps(prepare(args.output,args.slow_wait),indent=2))
    except (OSError, ValueError) as exc:
        parser.exit(2,str(exc)+'\n')
