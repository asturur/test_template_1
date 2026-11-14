import hashlib,struct,json
from pathlib import Path
from unicorn import *
from unicorn.arm_const import *
p=Path('scratch/calendar-ipc-narrow-20261114');rom=Path('build/firmware/nem4-factory/core.bin').read_bytes();assert hashlib.sha256(rom).hexdigest()=='be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524';blob=(p/'trace.bin').read_bytes();cases=0
for who in ('AGN import',):
 for args in (0,0xdeadbeef):
  for flags in (0,0x60000000,0x90000000):
   for result in (0,0xffffffed):
    for thumb in (0,1):
     u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x50000000,0x1400000);u.mem_write(0x50000000,rom);u.mem_write(0x511b8000,blob);u.mem_write(0x5085bab4,struct.pack('<I',0x511b8000));u.mem_map(0x80000000,0x100000)
     u.mem_write(0x80002000,struct.pack('<I',0x1234));regs=[UC_ARM_REG_R0+i for i in range(13)];vals=[0x100+i for i in range(13)];vals[:3]=[0x80002000,17,args];lr=0x80000000|thumb;calls=[];logs=[];names=[]
     def code(c,a,n,d):
      if a==0x80000000:c.emu_stop();return
      if a==0x503b2640:
       dest=c.reg_read(UC_ARM_REG_R0);handle=struct.unpack('<I',c.mem_read(c.reg_read(UC_ARM_REG_R1),4))[0];name=who if handle==0xffff8001 else '!AgendaServer';names.append(handle);data=name.encode('utf-16-le');c.mem_write(dest,struct.pack('<II',0x30000000|len(name),256)+data)
      elif a==0x503b409c:
       desc=c.reg_read(UC_ARM_REG_R0);length,addr=struct.unpack('<II',c.mem_read(desc,8));fmt=bytes(c.mem_read(addr,(length&0xfffffff)*2)).decode('utf-16-le');logs.append((fmt,c.reg_read(UC_ARM_REG_R1),c.reg_read(UC_ARM_REG_R2),c.reg_read(UC_ARM_REG_R3)))
      elif a==0x503b767c:
       calls.append([c.reg_read(x) for x in regs[:3]]);assert calls[-1]==vals[:3];c.reg_write(UC_ARM_REG_R0,result);c.reg_write(UC_ARM_REG_CPSR,(c.reg_read(UC_ARM_REG_CPSR)&0x0fffffff)|flags);c.reg_write(UC_ARM_REG_PC,c.reg_read(UC_ARM_REG_LR));return
      else:return
      for r in regs[:4]+[UC_ARM_REG_R12]:c.reg_write(r,0x55555555)
      c.reg_write(UC_ARM_REG_CPSR,(c.reg_read(UC_ARM_REG_CPSR)&0x0fffffff)|0xa0000000);c.reg_write(UC_ARM_REG_PC,c.reg_read(UC_ARM_REG_LR))
     u.hook_add(UC_HOOK_CODE,code);u.reg_write(UC_ARM_REG_CPSR,0x10|flags);u.reg_write(UC_ARM_REG_SP,0x800ff000);u.reg_write(UC_ARM_REG_LR,lr)
     for r,v in zip(regs,vals):u.reg_write(r,v)
     u.emu_start(0x5085baad,0,count=5000)
     assert u.reg_read(UC_ARM_REG_PC)==0x80000000
     assert u.reg_read(UC_ARM_REG_R0)==result
     assert u.reg_read(UC_ARM_REG_SP)==0x800ff000
     assert u.reg_read(UC_ARM_REG_LR)==lr
     assert u.reg_read(UC_ARM_REG_CPSR)&0xf000003f==flags|0x10|(thumb<<5)
     for r,v in zip(regs[4:12],vals[4:12]):assert u.reg_read(r)==v
     assert len(calls)==1
     assert len(logs)==2
     if logs:assert logs[0][1:]==(17,0x1234,lr) and logs[1][1:]==(17,0x1234,result)
     assert names==[]
     assert bytes(u.mem_read(0x503bab38,16))==rom[0x3bab38:0x3bab48]
     cases+=1
print('PASS',cases,'Calendar sync observer: single original call, exact args/result, callee regs/SP/flags, ARM/Thumb return, AGN import thunk only, no FullName, NULL/unmapped IPC pointers never dereferenced')
