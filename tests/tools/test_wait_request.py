"""Exercise the narrowed wait hook against private NEM-4 EUser bytes."""
from pathlib import Path
import struct
from unicorn import Uc, UC_ARCH_ARM, UC_MODE_ARM, UC_HOOK_CODE
from unicorn.arm_const import *
root=Path(__file__).resolve().parents[2]
blob=(root/'build/firmware-overlays/exit-trace/trace.bin').read_bytes()
for match,ipc,api in ((False,32,0x503df32d),(True,32,0x503df32d),(True,32,0x503df417),(True,36,0x503df597),(True,36,0x503df32d),(True,99,0x503df32d)):
 u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x50000000,0x1400000);u.mem_write(0x50000000,(root/'firmware/SYM.ROM').read_bytes());u.mem_write(0x511b6000,blob);u.mem_map(0x400000,0x400000)
 assert bytes(u.mem_read(0x503b247c,4))==struct.pack('<I',0xe2844001)
 vals=[1,2,3,4,19 if match else 18,0x403f0c,7,ipc,9,10,11,12,13,0x403f00,0x50901235]
 regs=[UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3,UC_ARM_REG_R4,UC_ARM_REG_R5,UC_ARM_REG_R6,UC_ARM_REG_R7,UC_ARM_REG_R8,UC_ARM_REG_R9,UC_ARM_REG_R10,UC_ARM_REG_R11,UC_ARM_REG_R12,UC_ARM_REG_SP,UC_ARM_REG_LR]
 u.reg_write(UC_ARM_REG_CPSR,0xa0000010)
 for r,v in zip(regs,vals):u.reg_write(r,v)
 u.mem_write(0x403f00,struct.pack('<9I',21,22,0x503b76c0,0x80000001,25,26,27,28,0x503bad7c));u.mem_write(0x403f34,struct.pack('<9I',api,0x50aabbcd,0,0,0,0x50ccdd01,0,0,0x50eeff01));logs=[]
 def hook(u,a,n,d):
  if a==0x503b2480:u.emu_stop()
  elif a==0x503b409c:
   h,p=struct.unpack('<II',u.mem_read(u.reg_read(UC_ARM_REG_R0),8));fmt=bytes(u.mem_read(p,(h&0xfffffff)*2)).decode('utf-16le');args=[u.reg_read(r) for r in regs[1:4]];logs.append((fmt,args));lr=u.reg_read(UC_ARM_REG_LR)
   for r in regs[:4]+[UC_ARM_REG_R12]:u.reg_write(r,0xdeadbeef)
   u.reg_write(UC_ARM_REG_CPSR,0x60000010);u.reg_write(UC_ARM_REG_PC,lr)
 u.hook_add(UC_HOOK_CODE,hook);u.emu_start(0x511b6018,0,count=5000)
 assert u.reg_read(UC_ARM_REG_PC)==0x503b2480
 for r,v in zip(regs,vals):assert u.reg_read(r)==(v+1 if r==UC_ARM_REG_R4 else v)
 assert u.reg_read(UC_ARM_REG_CPSR)&0xf0000000==0xa0000000
 if match:
  if (ipc==32 and api in (0x503df32d,0x503df417)) or (ipc==36 and api==0x503df597):
   assert len(logs)==1 and logs[0][1]==[ipc,api,0x50aabbcd if ipc==36 else 0x50eeff01 if api==0x503df417 else 0x50ccdd01]
  else:assert not logs
 else:assert not logs
print('PASS wait-request trace: caller/status/own-stack, scope, original instruction, all registers/flags/SP')
