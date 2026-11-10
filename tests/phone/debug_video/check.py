#!/usr/bin/env python3
"""Independently compare rendered HDL pixels with the documented text layout."""
from pathlib import Path
import sys
sys.path.insert(0,str(Path('tools').resolve()))
from generate_debug_font import outputs
assert Path('rtl/ngage_debug_font.hex').read_text()==outputs()['rtl/ngage_debug_font.hex']
font=bytes.fromhex(Path('rtl/ngage_debug_font.hex').read_text())
values=[0x12345678+i for i in range(24)]
values[16]=0x08000000;values[20]=2;values[21]=0x3f;values[22]=0x21
labels=['FETCH PC','LAST FETCH PC','LAST FETCH OP','CPSR','CYCLES','FETCH COUNT','BUS ADDR','BUS WRITE','BUS READ','BUS FLAGS','BUS ACKS','BUS ERRORS','WAIT NOW','WAIT MAX','LAST BUS ADR','LAST BUS DATA','DATA FAULT','FAULT FETCHPC','FAULT DATA','FAULT FLAGS','FAULT REASON','BOOT FLAGS','CPU FLAGS','KEYS HELD']
lines=['N-GAGE LIVE DEBUG','HEX VALUES - SNAPSHOT 4 HZ','PC IS FETCH VA']
side=['PLL','ROM','SDRAM','BOARD','SAVE','FAULT','EXPORT','LCD/ERR','RESET','IRQ','FIQ','CLAIM','READY','MEMREQ','RAM','FLASH','FLASH IO','RUN','ROM ERR','SAVE ERR','SAVE BUS','RESETREQ','SAVING','LOAD BLK']
for i,label in enumerate(labels):
 line=f'{label:<14}{values[i]:08X}'
 if i<len(side):line+='  '+f'{side[i]:<8} '+str((values[21 if i<8 or i>=17 else 22]>>(i if i<8 else i-8 if i<17 else i-9))&1)
 lines.append(line)
lines+=['PANIC 65637845 6F697470 00010003 MASK 7','FAULT FLAGS: SEE LIVE-CONTROLS DOC','KEYS HELD SHOWS NOKIA INPUT BITS']
lines=[list(s.ljust(40)) for s in lines];lines[0][38]='.'
raw=Path('build/sim/unit-debug-video/screen.ppm').read_bytes();head,wh,mx,pixels=raw.split(b'\n',3)
assert (head,wh,mx)==(b'P6',b'320 240',b'255')
expected=bytearray()
for y in range(240):
 for x in range(320):
  row,col=y//8,x//8;c=lines[row][col]
  lit=(font[ord(c)*8+y%8]>>(7-x%8))&1
  color=(0,0,17)
  if lit:
   if 3<=row<27 and col==33:
    item=row-3
    if item<5:color=(0,255,0) if c=='1' else (255,68,68)
    elif item in (5,7,18,19,23):color=(255,68,68) if c=='1' else (153,153,153)
    elif item in (8,21):color=(255,170,0) if c=='1' else (0,255,0)
    else:color=(0,255,255) if c=='1' else (153,153,153)
   elif row<3:color=(0,255,255)
   elif col<14:color=(153,153,153)
   else:color=(255,255,255)
  expected.extend(color)
assert pixels==expected,next((f'pixel {i//3}: {a} != {b}' for i,(a,b) in enumerate(zip(pixels,expected)) if a!=b),'size mismatch')
# Standalone artifact for visual inspection.
import struct,zlib
scaled=bytearray()
for y in range(240):
 row=b''.join(pixels[(y*320+x)*3:(y*320+x+1)*3]*3 for x in range(320))
 scaled.extend((b'\0'+row)*3)
def chunk(kind,data):
 return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',960,720,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(scaled))+chunk(b'IEND',b'')
Path('build/sim/unit-debug-video/screen.png').write_bytes(png)
print('PASS every diagnostic raster pixel matches independent text/font reference')
