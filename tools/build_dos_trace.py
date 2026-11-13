#!/usr/bin/env python3
"""Build the NEM4 DOS self-test observer, preserving the native event value."""
import hashlib,json,struct,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BASE=0x511b8000

def main():
 out=ROOT/'build/firmware-overlays/dos-trace';out.mkdir(parents=True,exist_ok=True)
 (out/'trace.ld').write_text('ENTRY(dos_trace)\ndebug_print = 0x503b409c;\nSECTIONS { .text 0x511b8000 : { *(.text*) } /DISCARD/ : { *(.ARM*) *(.comment) } }\n')
 subprocess.run(['arm-none-eabi-gcc','-c','-march=armv4t','-mthumb',str(ROOT/'firmware_overlays/diagnostics/dos_trace.S'),'-o',str(out/'trace.o')],check=True)
 subprocess.run(['arm-none-eabi-ld','-T',str(out/'trace.ld'),str(out/'trace.o'),'-o',str(out/'trace.elf')],check=True)
 subprocess.run(['arm-none-eabi-objcopy','-O','binary',str(out/'trace.elf'),str(out/'trace.bin')],check=True)
 data=(out/'trace.bin').read_bytes();assert len(data)<4096 and len(data)%4==0
 rom=(ROOT/'firmware/SYM.ROM').read_bytes();changes={}
 for call,old in ((0xfc16c0,0xf97cf000),(0xfc195e,0xf82df000)):
  assert struct.unpack_from('<I',rom,call)[0]==old
  delta=BASE-(0x50000000+call+4)
  instruction=struct.pack('<HH',0xf000|((delta>>12)&0x7ff),0xf800|((delta>>1)&0x7ff))
  for i,value in enumerate(instruction):changes[call+i]=value
 records=[(0x11b8000+i,0xffffffff,struct.unpack_from('<I',data,i)[0]) for i in range(0,len(data),4)]
 hooks=sorted({off&~3 for off in changes})
 for off in hooks:
  new=bytes(changes.get(off+i,rom[off+i]) for i in range(4))
  records.append((off,struct.unpack_from('<I',rom,off)[0],int.from_bytes(new,'little')))
 result=dict(base=BASE,bytes=len(data),sha256=hashlib.sha256(data).hexdigest(),hooks=hooks,records=sorted(records))
 (out/'trace.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:v for k,v in result.items() if k!='records'},indent=2))
if __name__=='__main__':main()
