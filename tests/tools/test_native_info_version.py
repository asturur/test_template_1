"""Original DSP-version receiver -> INFO builder -> unchanged RF startup check.

Synthetic device version bytes are input data. ROM instructions are untouched.
Allocation/libc, platform-type and optional tracing leaves are fixture services.
"""
from pathlib import Path
import hashlib,struct
from unicorn import Uc,UC_ARCH_ARM,UC_MODE_ARM,UC_HOOK_CODE
from unicorn.arm_const import *
ROOT=Path(__file__).resolve().parents[2]
rom=(ROOT/'firmware/THC N-Gage ROM Dump/ngage-gsmstuff-0x5149D280.dll').read_bytes()
assert hashlib.sha256(rom).hexdigest()=='e5870e918c90d9c7a6403eb0ee305d174e906aeae0a7fa8069e85a18aeec7aa1'
body=rom[96:];base=0x5149d280;stop=0x51400000

def verify(revision):
 u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x51400000,0x400000);u.mem_write(base,body)
 u.mem_map(0x80000000,0x120000);heap=0x80101000;freed=[]
 def cstr(a):
  out=bytearray()
  for i in range(4096):
   b=u.mem_read(a+i,1)[0]
   if b==0:return bytes(out)
   out.append(b)
  raise AssertionError('unbounded fixture string')
 def hook(u,a,n,data):
  nonlocal heap
  if a==stop:u.emu_stop();return
  r=[u.reg_read(x) for x in (UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2)]
  if a in (0x516c74ec,0x514b9a44):
   assert r[0]<4096;u.mem_write(heap,bytes((r[0]+15)&~15));u.reg_write(UC_ARM_REG_R0,heap);heap+=(r[0]+31)&~15
  elif a==0x516c752c:u.mem_write(r[0],bytes([r[1]&255])*r[2])
  elif a==0x516c76c4:u.mem_write(r[0],bytes(u.mem_read(r[1],r[2])))
  elif a==0x516c7574:u.mem_write(r[0],cstr(r[1])+b'\0')
  elif a==0x516c7634:u.reg_write(UC_ARM_REG_R0,len(cstr(r[0])))
  elif a==0x516c7524:u.reg_write(UC_ARM_REG_R0,r[0]%r[1])
  elif a==0x516c7594:u.reg_write(UC_ARM_REG_R0,r[0]//r[1])
  elif a==0x514c1604:u.reg_write(UC_ARM_REG_R0,1) # Selected native platform profile.
  elif a==0x514b9ab4:freed.append(r[0])
  elif a==0x514bd538:pass # Optional native trace sink.
  else:return
  u.reg_write(UC_ARM_REG_PC,u.reg_read(UC_ARM_REG_LR))
 u.hook_add(UC_HOOK_CODE,hook)
 def call(entry,args):
  u.reg_write(UC_ARM_REG_CPSR,0x13);u.reg_write(UC_ARM_REG_SP,0x8011f000);u.reg_write(UC_ARM_REG_LR,stop|1)
  for r,v in zip((UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3),args):u.reg_write(r,v)
  u.emu_start(entry|1,0,count=100000)
  assert u.reg_read(UC_ARM_REG_PC)==stop and u.reg_read(UC_ARM_REG_SP)==0x8011f000
  assert bytes(u.mem_read(base,len(body)))==body
  return u.reg_read(UC_ARM_REG_R0)
 # Native receiver converts one packed version component into its own string.
 p=0x80100100;result=0x80100200
 u.mem_write(p,bytes((0x20,0xa1,1,revision)));u.mem_write(result,b'\0')
 call(0x515920d0,(0xf1a1,p,result))
 ptr=struct.unpack('<I',u.mem_read(0x80009d3c,4))[0]
 assert cstr(ptr)==f'{revision:02d}'.encode(),cstr(ptr)
 # Let original INFO code form the reply and its RF-version subblock.
 u.mem_write(p,bytes.fromhex('0c070020'))
 reply=call(0x5164c3ec,(p,))
 actual=bytes(u.mem_read(reply,12))
 assert actual[:8]==bytes.fromhex('0c08000154080003'),actual.hex()
 assert actual[8:12]==f'{revision:02d}'.encode()+b'\0\0',actual.hex()
 # Original native startup check must pass03 and fail04, without registry edits.
 state=struct.unpack_from('<I',body,0x5164ab48-base)[0]
 response=struct.unpack_from('<I',body,0x5164ab30-base)[0]
 u.mem_write(state,b'\1');u.mem_write(response,struct.pack('<I',reply))
 assert call(0x516a60c0,(result,))==0
 assert bytes(u.mem_read(result,1))==bytes((int(revision!=3),))
 assert freed==[reply]
 return actual.hex()

for revision in (3,4):verify(revision)
print('PASS original DSP RF-version receiver, native INFO subblock builder and startup test:03 passes/04 fails, no instruction or test-table modifications')
