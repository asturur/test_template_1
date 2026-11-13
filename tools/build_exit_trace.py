#!/usr/bin/env python3
"""Build the private NEM-4 exit diagnostic payload; never changes firmware."""
import hashlib
import json
from pathlib import Path
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
HOOKS = {'exit': 0x503b4718, 'panic': 0x503b46e0, 'kill': 0x503b7fb8,
         'terminate': 0x503b7fe4, 'thread_panic': 0x503b8010,
         'descriptor_bounds': 0x503a2b48, 'wait_request': 0x503b247c}
BASE = 0x511B6000


def main():
    out = ROOT/'build/firmware-overlays/exit-trace'
    out.mkdir(parents=True, exist_ok=True)
    formats = []
    for name in [*HOOKS, 'wait_stack', 'dsy_message', 'target_name', 'view_context', *['ctx'+str(i) for i in range(6)]]:
        text = 'X '+name.upper()+' a0=%08x a1=%08x a2=%08x lr=%08x sp=%08x cpsr=%08x r6=%08x'
        if name == 'wait_request':
            text = 'X FILE_WAIT ipc=%08x file_api=%08x caller=%08x'
        if name == 'wait_stack':
            text = 'X WAIT_STACK outer=%08x ipc=%08x args=%08x'
        if name == 'dsy_message':
            text = 'X DSY_MESSAGE w0=%08x w1=%08x w2=%08x caller=%08x'
        if name == 'target_name':
            text = 'X VIEW_TARGET %S'
        if name == 'view_context':
            text = 'X VIEW_CONTEXT ret=%08x len=%08x requests=%08x'
        if name.startswith('ctx'):
            text = 'X '+name.upper()+' %08x %08x %08x'
        formats += ['.balign 4', 'fmt_'+name+':',
                    '.word '+hex(0x10000000 | len(text))+', str_'+name,
                    'str_'+name+':', '.hword '+','.join(str(ord(c)) for c in text)]
    (out/'formats.inc').write_text('\n'.join(formats)+'\n')
    (out/'trace.ld').write_text('ENTRY(exit_trace)\ndebug_print = 0x503b409c;\nfull_name = 0x503b2640;\nthread_context = 0x503b32d0;\nsuspend_thread = 0x503b32e8;\nresume_thread = 0x503b32e0;\nrequest_count = 0x503b33a0;\n'
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
        old = (0xea003c0a if name == 'descriptor_bounds' else
               0xe2844001 if name == 'wait_request' else 0xe92d4000)
        records.append((entry-0x50000000,old,branch))
    result=dict(base=BASE,bytes=len(payload),sha256=hashlib.sha256(payload).hexdigest(),
                hooks=HOOKS,records=sorted(records))
    (out/'trace.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='records'},indent=2))


if __name__=='__main__':main()
