"""Execute the original NEM-4 MDI TX task and ring writer, without ROM edits."""
import hashlib
from pathlib import Path
import struct
from unicorn import Uc,UC_ARCH_ARM,UC_MODE_ARM,UC_HOOK_CODE,UC_HOOK_MEM_WRITE
from unicorn.arm_const import *
ROOT=Path(__file__).resolve().parents[2]
rom=(ROOT/'firmware/THC N-Gage ROM Dump/ngage-gsmstuff-0x5149D280.dll').read_bytes()
assert hashlib.sha256(rom).hexdigest()=='e5870e918c90d9c7a6403eb0ee305d174e906aeae0a7fa8069e85a18aeec7aa1'
body=rom[96:];base=0x5149d280;stop=0x51400000

def send(start):
 u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x51400000,0x400000);u.mem_write(base,body)
 u.mem_map(0x80000000,0x10000);u.mem_map(0x0c100000,4096)
 obj,state,hw,packet=0x80001000,0x80001100,0x80001200,0x80002000
 def word(a,v):u.mem_write(a,struct.pack('<I',v))
 def half(a,v):u.mem_write(a,struct.pack('<H',v))
 word(obj,hw);word(obj+4,state);word(hw+4,0x0c100000)
 word(hw+12,0x0c1003e8);word(hw+16,0x0c1003ea);half(hw+0x42,250)
 half(0x0c1003e8,start);half(0x0c1003ea,start)
 half(state+10,6);half(state+12,6);word(state+20,packet)
 # Authored Phonet frame at the native sender boundary: length is host-order.
 original=bytes.fromhex('007c00f106002a1b20a00200')
 u.mem_write(packet,original);freed=[];writes=[];notifies=[]
 def code(u,a,n,data):
  if a==stop:u.emu_stop();return
  if a==0x514bd538:pass # Native trace/inspection method, outside ring protocol.
  elif a in (0x514c08bc,0x514c0924):pass # RTOS semaphore take/release.
  elif a==0x516c75bc:notifies.append(u.reg_read(UC_ARM_REG_R0))
  elif a==0x516c7504:freed.append(u.reg_read(UC_ARM_REG_R0))
  else:return
  u.reg_write(UC_ARM_REG_PC,u.reg_read(UC_ARM_REG_LR))
 def write(u,access,address,size,value,data):
  if 0x0c100000<=address<0x0c101000:writes.append((address,size,value))
 u.hook_add(UC_HOOK_CODE,code);u.hook_add(UC_HOOK_MEM_WRITE,write)
 u.reg_write(UC_ARM_REG_CPSR,0x13);u.reg_write(UC_ARM_REG_SP,0x8000f000)
 u.reg_write(UC_ARM_REG_R0,obj);u.reg_write(UC_ARM_REG_LR,stop|1)
 u.emu_start(0x514c4869,0,count=20000)
 assert u.reg_read(UC_ARM_REG_PC)==stop and u.reg_read(UC_ARM_REG_SP)==0x8000f000
 expected=bytes.fromhex('007c00f100062a1b20a00200')
 actual=b''.join(bytes(u.mem_read(0x0c100000+2*((start+i)%250),2))[::-1] for i in range(6))
 assert actual==expected,(actual.hex(),expected.hex())
 assert struct.unpack('<H',u.mem_read(0x0c1003e8,2))[0]==(start+6)%250
 assert freed==[packet] and notifies==[0x20]
 assert u.mem_read(state+8,1)==b'\0' and u.mem_read(state+12,2)==b'\0\0'
 assert bytes(u.mem_read(base,len(body)))==body
 return writes

for start in (0,247):send(start)
print('PASS original MDI TX task/ring writer: Phonet length conversion, halfword byte order,250-word wrap, producer publication, request release; ROM unchanged')
