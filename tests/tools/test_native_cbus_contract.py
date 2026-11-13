"""Capture an unmodified NEM-4 CBUS write's native register protocol.

HAL read/write leaves are spied; their addresses are UPP register offsets.
This proves ordering/encoding, not physical CBUS serial timing or LRB2 behavior.
"""
import hashlib
from pathlib import Path
import struct
from unicorn import Uc, UC_ARCH_ARM, UC_MODE_ARM, UC_HOOK_CODE
from unicorn.arm_const import *
root=Path(__file__).resolve().parents[2]
rom=(root/'build/firmware/nem4-factory/core.bin').read_bytes()
assert hashlib.sha256(rom).hexdigest()=='be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524'
u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x50000000,0x1400000);u.mem_write(0x50000000,rom)
u.mem_map(0x80000000,0x10000)
stop=0x50000000;ops=[]
def hook(u,address,size,data):
 if address==stop:u.emu_stop();return
 if address==0x50383434:
  a=u.reg_read(UC_ARM_REG_R0);assert a==0x150422
  ops.append(('read',a,0x400));u.reg_write(UC_ARM_REG_R0,0x400)
 elif address==0x50383410:
  ops.append(('write',u.reg_read(UC_ARM_REG_R1),u.reg_read(UC_ARM_REG_R0)))
 else:return
 u.reg_write(UC_ARM_REG_PC,u.reg_read(UC_ARM_REG_LR))
u.hook_add(UC_HOOK_CODE,hook)
u.reg_write(UC_ARM_REG_CPSR,0x13);u.reg_write(UC_ARM_REG_SP,0x8000f000);u.reg_write(UC_ARM_REG_LR,stop)
u.mem_write(0x8000f000,struct.pack('<II',0,2))
for reg,v in ((UC_ARM_REG_R0,0x80000100),(UC_ARM_REG_R1,5),(UC_ARM_REG_R2,0x27),(UC_ARM_REG_R3,16)):u.reg_write(reg,v)
u.emu_start(0x503822bc,0,count=20000)
assert u.reg_read(UC_ARM_REG_PC)==stop and u.reg_read(UC_ARM_REG_R0)==0
assert u.reg_read(UC_ARM_REG_SP)==0x8000f000
assert ops==[('read',0x150422,0x400),('write',0x150420,15),('write',0x150422,0xa6),('write',0x150426,2),('read',0x150422,0x400)],ops
assert bytes(u.mem_read(0x50000000,len(rom)))==rom
print('PASS original CBUS client: idle poll before first transfer,16-bit configuration, chip5/register6 encoding, payload and completion poll; ROM unchanged')
