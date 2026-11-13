"""Qualify unchanged ADSP server packet framing/checksum/sequence primitives.

Input descriptor is synthetic, NOT a captured startup packet. Descriptor/libc
and allocator leaves are fixture services. RX excludes the TX55/55 preamble.
No firmware or production state is modified.
"""
from pathlib import Path
import struct
from unicorn import *
from unicorn.arm_const import *
ROOT=Path(__file__).resolve().parents[2]
r=(ROOT/'build/firmware/nem4-factory/core.bin').read_bytes()
import hashlib
assert hashlib.sha256(r).hexdigest()=='be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524'
u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x50000000,0x1400000);u.mem_write(0x50000000,r);u.mem_map(0x80000000,0x20000)
stop=0x80000000;obj=stop+0x100;des=stop+0x300;payload=stop+0x500;heap=stop+0x10000
p=bytes.fromhex('007c0082000a00000e2b000700420000')
def word(a,v):u.mem_write(a,struct.pack('<I',v))
def rd(a):return struct.unpack('<I',u.mem_read(a,4))[0]
def initdes(a,p,n):u.mem_write(a,struct.pack('<III',0x20000000|n,1024,p))
initdes(des,payload,len(p));u.mem_write(payload,p)
def append(a,data):
 n=rd(a)&0xfffffff;ptr=rd(a+8);u.mem_write(ptr+n,data);word(a,0x20000000|n+len(data))
def hook(u,a,n,o):
 global heap
 if a==stop:u.emu_stop();return
 x=[u.reg_read(q) for q in (UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3)]
 if a==0x510ef988:
  word(heap,x[0]);u.reg_write(UC_ARM_REG_R0,heap);heap+=2048
 elif a==0x510ef808:initdes(x[0],x[1]+4,0)
 elif a==0x510ef6bc:append(x[0],bytes([x[1]&255]))
 elif a==0x510ef844:append(x[0],bytes(u.mem_read(rd(x[1]+8),rd(x[1])&0xfffffff)))
 elif a==0x510ef5f0:u.reg_write(UC_ARM_REG_R0,rd(x[0]+8)+x[1])
 elif a==0x510ef9a0:u.reg_write(UC_ARM_REG_R0,rd(x[0]+8))
 else:return
 u.reg_write(UC_ARM_REG_PC,u.reg_read(UC_ARM_REG_LR))
u.hook_add(UC_HOOK_CODE,hook)
def call(a,*args):
 for q,v in [(UC_ARM_REG_CPSR,0x13),(UC_ARM_REG_SP,0x8000f000),(UC_ARM_REG_LR,stop|1)]+list(zip((UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3),args)):u.reg_write(q,v)
 u.emu_start(a|1,0,count=100000)
 assert u.reg_read(UC_ARM_REG_PC)==stop
call(0x510ee1f4,obj,des);call(0x510ee088,obj,3);call(0x510edc0c,obj)
size=rd(obj+4)&0xfffffff;data=bytes(u.mem_read(rd(obj+12),size))
assert size==22 and data.hex()=='555520780012000a00000e2b00070042000300002e0d'
# TX checksum deliberately excludes sync word. RX object has already consumed
# that preamble; verification includes its entire remaining packet.
rx=stop+0x700
initdes(rx+4,payload+0x800,size-2)
u.mem_write(payload+0x800,data[2:])
call(0x510edc6c,rx);assert u.reg_read(UC_ARM_REG_R0)==1
u.mem_write(payload+0x808,bytes([data[10]^1]))
call(0x510edc6c,rx);assert u.reg_read(UC_ARM_REG_R0)==0
# All eight sequence values retain the other flag bits and recompute checksum.
for seq in range(8):
 call(0x510ee088,obj,seq);call(0x510edc0c,obj)
 current=bytes(u.mem_read(rd(obj+12),size))
 assert current[17]&7==seq
 u.mem_write(payload+0x800,current[2:])
 call(0x510edc6c,rx);assert u.reg_read(UC_ARM_REG_R0)==1
print('PASS original ADSP packet: sync exclusion, checksum rejection, eight sequence values and unchanged ROM')
assert bytes(u.mem_read(0x50000000,len(r)))==r
