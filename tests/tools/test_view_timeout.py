from pathlib import Path
import struct,json
from unicorn import Uc,UC_ARCH_ARM,UC_MODE_ARM,UC_HOOK_CODE
from unicorn.arm_const import *
rom=Path('firmware/SYM.ROM').read_bytes()
BASE=0x50000000;RAM=0x100000;STOP=0x101000

def fixture(patched):
 u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(BASE,0x1400000);u.mem_write(BASE,rom);u.mem_map(RAM,0x10000)
 if patched:
  u.mem_write(0x5064bf68,struct.pack('<II',10000000,100000000))
 u.reg_write(UC_ARM_REG_SP,0x10f000);u.reg_write(UC_ARM_REG_LR,STOP|1)
 return u

def constructor(patched):
 u=fixture(patched)
 def hook(u,a,s,d):
  if a==STOP:u.emu_stop()
  elif a in (0x5064f034,0x5064f040):u.reg_write(UC_ARM_REG_PC,u.reg_read(UC_ARM_REG_LR))
 u.hook_add(UC_HOOK_CODE,hook);u.reg_write(UC_ARM_REG_R0,0x102000);u.reg_write(UC_ARM_REG_R2,0x12345678);u.emu_start(0x5064bf11,0,count=500)
 assert u.reg_read(UC_ARM_REG_PC)==STOP
 return bytes(u.mem_read(0x102000,0x90))
a=constructor(False);b=constructor(True)
assert struct.unpack_from('<II',a,0x80)==(1000000,10000000)
assert struct.unpack_from('<II',b,0x80)==(10000000,100000000)
assert a[:0x80]==b[:0x80] and a[0x88:]==b[0x88:]

def arm_timer(soft,hard,phase2=False):
 u=fixture(False);obj=0x102000;timer=0x103000
 u.mem_write(obj,struct.pack('<6I',0,timer,0,soft,hard,1 if phase2 else 0));u.reg_write(UC_ARM_REG_R0,obj);seen=[]
 def hook(u,a,s,d):
  if a==STOP:u.emu_stop()
  elif a==0x5064f1f8:
   seen.append((u.reg_read(UC_ARM_REG_R0),u.reg_read(UC_ARM_REG_R1)))
   u.reg_write(UC_ARM_REG_PC,u.reg_read(UC_ARM_REG_LR))
 u.hook_add(UC_HOOK_CODE,hook);u.emu_start(0x5064ca2d if phase2 else 0x5064c9c5,0,count=500)
 assert u.reg_read(UC_ARM_REG_PC)==STOP and len(seen)==1
 assert seen[0]==(timer,hard-soft if phase2 else soft)
 return seen[0][1]
result={'original_us':[arm_timer(1000000,10000000),arm_timer(1000000,10000000,True)],'extended_us':[arm_timer(10000000,100000000),arm_timer(10000000,100000000,True)],'constructor_other_bytes_identical':True,'limits':'Original Thumb constructor and timer scheduling execute in Unicorn; external base constructors and scheduling import are leaf stubs. No full OS/hardware qualification.'}
print(json.dumps(result,indent=2))
