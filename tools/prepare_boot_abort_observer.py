#!/usr/bin/env python3
"""Prepare a terminal-only NEM-4 abort observer; never connects or applies it.

Only a vector that would already halt at low0x60c logs LR/FAR/FSR through the
existing DDR panic recorder. Normal high-address vector handoffs retain their
original registers/flags. The terminal path uses R0..R3 as scratch, retains
SP/LR/SPSR and ends at the original halt. No stack, LDM/STM or checksum bypass.
"""
import argparse
import hashlib
import inspect
import json
from pathlib import Path
import struct
import subprocess
import ngage_runtime_bt as runtime
from prepare_native_observer import held_fresh
import service_firmware

ROOT=Path(__file__).resolve().parents[1]

def build(out,first_abort=False):
    out.mkdir(parents=True,exist_ok=True)
    source=ROOT/'tools/mister/boot_abort_observer.S'
    (out/'link.ld').write_text('SECTIONS { .text 0x20 : { *(.text*) } /DISCARD/ : { *(.ARM.attributes) *(.comment) *(.note*) } }')
    subprocess.run(['arm-none-eabi-gcc','-c','-mcpu=arm920t',*(['-DFIRST_ABORT'] if first_abort else []),str(source),'-o',str(out/'observer.o')],check=True)
    subprocess.run(['arm-none-eabi-ld','-T',str(out/'link.ld'),str(out/'observer.o'),'-o',str(out/'observer.elf')],check=True)
    subprocess.run(['arm-none-eabi-objcopy','-O','binary',str(out/'observer.elf'),str(out/'observer.bin')],check=True)
    blob=(out/'observer.bin').read_bytes()
    assert len(blob)==96
    raw=bytearray(b'\xff'*service_firmware.BACKING_SIZE)
    for kind,spec in service_firmware.PROFILES.items():
        original=ROOT/'firmware/NEM-04 v.04.03 N-GAGE'/spec[0]
        service_firmware.apply(raw,service_firmware.parse(original.read_bytes(),kind),kind)
    assert hashlib.sha256(raw).hexdigest()==runtime.ROM_SHA
    assert raw[0x20:0x80]==bytes(96)
    records=[(0x20+i,0,struct.unpack_from('<I',blob,i)[0]) for i in range(0,96,4)]
    records += [(0x10,0xea000179,0xea000002),(0xc,0xea000176,0xea000007)]
    original_checksum_bytes=bytes(raw[0x9000:0x11b5000])
    for off,old,new in records:
        assert struct.unpack_from('<I',raw,off)[0]==old
        struct.pack_into('<I',raw,off,new)
    assert raw[0x9000:0x11b5000]==original_checksum_bytes
    report=dict(first_abort_breakpoint=first_abort,records=len(records),original_rom_sha256=runtime.ROM_SHA,
                instrumented_rom_sha256=hashlib.sha256(raw).hexdigest(),
                checksum_range_bytes_unchanged=True,functional_startup_substitutions=False,
                terminal_scratch_registers=['r0','r1','r2','r3'],
                normal_vector_handoffs_preserved=not first_abort,stack_used=False,
                source_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    script='import argparse,hashlib,json,mmap,os,struct,time\n'
    for name in ('BASE','SIZE','ROM_SIZE','ROM_SHA'):script+=name+'='+repr(getattr(runtime,name))+'\n'
    script+='\n'+inspect.getsource(runtime.snapshot)+'\n'+inspect.getsource(held_fresh)
    script+='\nrecords='+repr(records)+'\nreport='+repr(report)+'\n'
    script+='''
parser=argparse.ArgumentParser(description='Terminal-only abort observer; reload removes it')
parser.add_argument('--apply',action='store_true');args=parser.parse_args()
fd=os.open('/dev/mem',(os.O_RDWR if args.apply else os.O_RDONLY)|os.O_SYNC)
try:
 with mmap.mmap(fd,SIZE,access=mmap.ACCESS_WRITE if args.apply else mmap.ACCESS_READ,offset=BASE) as memory:
  if hashlib.sha256(memory[:ROM_SIZE]).hexdigest()!=ROM_SHA:raise ValueError('requires exact original firmware')
  for off,old,new in records:
   if struct.unpack_from('<I',memory,off)[0]!=old:raise ValueError('original word mismatch')
  first=snapshot(memory);report['fresh_held']=bool(held_fresh(first));report['applied']=False
  if args.apply:
   if not held_fresh(first):raise ValueError('fresh physical Hold, saved RunOff, saveOff, completed restore required')
   deadline=time.monotonic()+3
   while True:
    time.sleep(.1);second=snapshot(memory)
    if not held_fresh(second):raise ValueError('freshness changed; no write made')
    if first[2]!=second[2]:break
    if time.monotonic()>=deadline:raise ValueError('snapshot not advancing')
   applied=[]
   try:
    # The prepared order publishes code before either vector.
    for off,old,new in records:struct.pack_into('<I',memory,off,new);applied.append((off,old,new))
    for off,old,new in records:
     if struct.unpack_from('<I',memory,off)[0]!=new:raise ValueError('write readback mismatch')
    if hashlib.sha256(memory[:ROM_SIZE]).hexdigest()!=report['instrumented_rom_sha256']:raise ValueError('full image mismatch')
    if not held_fresh(snapshot(memory)):raise ValueError('CPU started during preparation; reload required')
   except Exception:
    for off,old,new in reversed(applied):struct.pack_into('<I',memory,off,old)
    raise
   report['applied']=True
  print(json.dumps(report))
finally:os.close(fd)
'''
    (out/'observer.py').write_text(script)
    (out/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
    return report

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',required=True,type=Path)
    parser.add_argument('--first-abort',action='store_true',help='Diagnostic breakpoint: log and halt the FIRST abort, including normally recoverable faults')
    args=parser.parse_args()
    print(json.dumps(build(args.out,args.first_abort),indent=2))
