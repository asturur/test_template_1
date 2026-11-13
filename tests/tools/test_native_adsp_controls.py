"""Unchanged ADSPCTRL driver control methods and HAL, with CBUS leaf spied.

This establishes register operations, not DSP firmware or successful startup.
"""
from pathlib import Path
import hashlib,struct,json
from unicorn import *
from unicorn.arm_const import *
root=Path(__file__).resolve().parents[2]
rom=(root/'build/firmware/nem4-factory/core.bin').read_bytes()
assert hashlib.sha256(rom).hexdigest()=='be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524'
allops=[]
for control in range(6):
 for value in (0,1):
  u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x50000000,0x1400000);u.mem_write(0x50000000,rom)
  u.mem_map(0x80000000,0x10000);u.mem_map(0x58000000,0x160000)
  obj=0x80000100;cbus=0x80000300;vt=0x80000400;arg=0x80000500;stop=0x80000000;spy=stop+4;ops=[]
  u.mem_write(obj+0x38,struct.pack('<I',cbus));u.mem_write(cbus,struct.pack('<I',vt));u.mem_write(vt+0x14,struct.pack('<I',spy));u.mem_write(arg,struct.pack('<I',value))
  def hook(u,a,n,data):
   if a==stop:u.emu_stop()
   elif a==spy:
    r=[u.reg_read(x) for x in (UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3)]
    sp=u.reg_read(UC_ARM_REG_SP);stack=struct.unpack('<III',u.mem_read(sp,12))
    ops.append(['cbus',*r[1:],*stack]);u.reg_write(UC_ARM_REG_R0,0);u.reg_write(UC_ARM_REG_PC,u.reg_read(UC_ARM_REG_LR))
  def mem(u,kind,a,size,value,data):
   if kind==UC_MEM_WRITE:ops.append(['write',hex(a),size,value])
   else:ops.append(['read',hex(a),size])
  u.hook_add(UC_HOOK_CODE,hook);u.hook_add(UC_HOOK_MEM_READ|UC_HOOK_MEM_WRITE,mem,begin=0x58000000,end=0x5815ffff)
  for r,v in ((UC_ARM_REG_CPSR,0x13),(UC_ARM_REG_SP,0x8000f000),(UC_ARM_REG_LR,stop),(UC_ARM_REG_R0,obj),(UC_ARM_REG_R1,control),(UC_ARM_REG_R2,arg)):u.reg_write(r,v)
  u.emu_start(0x510e9734,0,count=10000)
  assert u.reg_read(UC_ARM_REG_PC)==stop and u.reg_read(UC_ARM_REG_SP)==0x8000f000
  assert bytes(u.mem_read(0x50000000,len(rom)))==rom
  allops.append({'control':control,'value':value,'result':u.reg_read(UC_ARM_REG_R0),'ops':ops})
for case in allops:
 c=case['control'];v=case['value'];ops=case['ops']
 assert case['result']==0
 if c in (0,1,3):
  bit={0:512,1:1,3:16384}[c]
  direction=0x5815020e if c==3 else 0x58150210
  mask=0x58150212 if c==3 else 0x58150214
  out=(0x58150202 if v else 0x58150204) if c==3 else (0x58150206 if v else 0x58150208)
  assert ops==[['read',hex(direction),2],['write',hex(direction),2,bit],
               ['read',hex(mask),2],['write',hex(mask),2,bit],['write',hex(out),2,bit]],case
 elif c==2:
  base=[['read','0x58120c14',4],['write','0x58120c14',4,0],
        ['read','0x58120c18',4],['write','0x58120c18',4,8]]
  cbus=['cbus',1,11,8,0,0 if v else 32,32 if v else 0]
  pin=['write',hex(0x58120c0c if v else 0x58120c10),4,8]
  assert ops==base+([cbus,pin] if v else [pin,cbus]),case
 else:
  clear,setbits=((0,240) if v else (240,0)) if c==4 else ((32,0) if v else (0,32))
  assert ops==[['cbus',1,15 if c==4 else 16,8,0,clear,setbits]],case
print('PASS original ADSPCTRL controls0..5 both levels: native HAL MMIO/order, CBUS chip/register/masks, stack and ROM unchanged')
