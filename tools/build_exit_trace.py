#!/usr/bin/env python3
"""Build the private NEM-4 exit diagnostic payload; never changes firmware."""
import hashlib
import json
from pathlib import Path
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
HOOKS = {'exit': 0x503b4718, 'panic': 0x503b46e0, 'kill': 0x503b7fb8,
         'terminate': 0x503b7fe4, 'thread_panic': 0x503b8010}
BASE = 0x511B6000


def main():
    out = ROOT/'build/firmware-overlays/exit-trace'
    out.mkdir(parents=True, exist_ok=True)
    formats = []
    for name in HOOKS:
        text = 'X '+name.upper()+' a0=%08x a1=%08x lr=%08x sp=%08x cpsr=%08x'
        formats += ['.balign 4', 'fmt_'+name+':',
                    '.word '+hex(0x10000000 | len(text))+', str_'+name,
                    'str_'+name+':', '.hword '+','.join(str(ord(c)) for c in text)]
    (out/'formats.inc').write_text('\n'.join(formats)+'\n')
    (out/'trace.ld').write_text('ENTRY(exit_trace)\ndebug_print = 0x503b409c;\n'
        'SECTIONS { .text 0x511b6000 : { *(.text*) } '
        '/DISCARD/ : { *(.ARM.attributes) *(.comment) *(.note*) } }\n')
    source = ROOT/'firmware_overlays/diagnostics/exit_trace.S'
    subprocess.run(['arm-none-eabi-gcc','-c','-march=armv4t','-marm','-Wa,-I'+str(out),
                    str(source),'-o',str(out/'trace.o')],check=True)
    subprocess.run(['arm-none-eabi-ld','-T',str(out/'trace.ld'),str(out/'trace.o'),
                    '-o',str(out/'trace.elf')],check=True)
    subprocess.run(['arm-none-eabi-objcopy','-O','binary',str(out/'trace.elf'),
                    str(out/'trace.bin')],check=True)
    payload=(out/'trace.bin').read_bytes()
    if len(payload)>4096 or len(payload)%4:raise ValueError('payload bounds/alignment')
    symbols={p[2]:int(p[0],16) for line in subprocess.check_output(
        ['arm-none-eabi-nm',str(out/'trace.elf')],text=True).splitlines() if len(p:=line.split())==3}
    records=[(BASE-0x50000000+i,0xffffffff,struct.unpack_from('<I',payload,i)[0])
             for i in range(0,len(payload),4)]
    for name,entry in HOOKS.items():
        target=symbols['trace_'+name]
        branch=0xea000000|(((target-entry-8)//4)&0xffffff)
        records.append((entry-0x50000000,0xe92d4000,branch))
    result=dict(base=BASE,bytes=len(payload),sha256=hashlib.sha256(payload).hexdigest(),
                hooks=HOOKS,records=sorted(records))
    (out/'trace.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='records'},indent=2))


if __name__=='__main__':main()
