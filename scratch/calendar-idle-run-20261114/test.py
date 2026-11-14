from pathlib import Path
import struct,itertools
from unicorn import *
from unicorn.arm_const import *
p=Path(__file__).parent;rom=Path('build/firmware/nem4-factory/core.bin').read_bytes();blob=(p/'trace.bin').read_bytes();symbols={a[2]:int(a[0],16) for l in (p/'symbols.txt').read_text().splitlines() if len(a:=l.split())==3};cases=0
for (name,entry),mode,flags,callback,thumb in itertools.product([('start',0x50399d70),('run',0x50399dac),('ready',0x50399da4)],[0x10,0x13,0x12,0x1b],[0,0x60000000,0x90000000],[0,0x50833d45,0x5085b001,0x5089495d,0x5099fe41,0x509a0539,0x509b30f9],[0,1]):
 out=[]
 for traced in [False,True]:
  u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x50000000,0x1400000);u.mem_write(0x50000000,rom);u.mem_write(0x511b8000,blob);u.mem_map(0x80000000,0x100000);u.mem_write(0x80002018,struct.pack('<II',callback,0xdeadbeef));regs=[UC_ARM_REG_R0+i for i in range(13)];vals=[0x100+i for i in range(13)];vals[:3]=[0x80002000,callback,0xdeadbeef];logs=[]
  if name=='ready':vals[4]=0x80002000
  u.mem_write(0x800ff000,struct.pack('<II',0x33445566,0x80000000|thumb));u.mem_write(0x80002004,struct.pack('<II',0,1));u.mem_write(0x80002014,struct.pack('<I',0xffffffec))
  def code(c,a,n,d):
   if a==entry+4:c.emu_stop();return
   if a==0x503b409c:
    desc=c.reg_read(UC_ARM_REG_R0);length,addr=struct.unpack('<II',c.mem_read(desc,8));fmt=bytes(c.mem_read(addr,(length&0xfffffff)*2)).decode('utf-16-le');logs.append((fmt,tuple(c.reg_read(r) for r in regs[1:4])))
    for r in regs[:4]+[UC_ARM_REG_R12]:c.reg_write(r,0x55555555)
    c.reg_write(UC_ARM_REG_CPSR,(c.reg_read(UC_ARM_REG_CPSR)&0x0fffffff)|0xa0000000);c.reg_write(UC_ARM_REG_PC,c.reg_read(UC_ARM_REG_LR))
  u.hook_add(UC_HOOK_CODE,code);u.reg_write(UC_ARM_REG_CPSR,mode|flags);u.reg_write(UC_ARM_REG_SPSR,0x90000030);u.reg_write(UC_ARM_REG_SP,0x800ff000);u.reg_write(UC_ARM_REG_LR,0x80000000|thumb)
  for r,v in zip(regs,vals):u.reg_write(r,v)
  if traced:u.mem_write(entry,struct.pack('<I',0xea000000|(((symbols[name+'_trace']-entry-8)//4)&0xffffff)))
  u.emu_start(entry,0,count=2000);assert u.reg_read(UC_ARM_REG_PC)==entry+4
  logged=mode==0x10 and (0x50833d44<=callback<0x5089495c or 0x5099ec44<=callback<0x509b30f8)
  assert len(logs)==int(traced and logged)
  if logs:assert logs==[(f'I {name.upper()} object=%08x callback=%08x param=%08x',(0x80002000,callback,0xdeadbeef))] if name!='ready' else logs==[('I READY object=%08x status=%08x priority=%08x',(0x80002000,0,0xffffffec))]
  out.append(([u.reg_read(r) for r in regs]+[u.reg_read(r) for r in [UC_ARM_REG_SP,UC_ARM_REG_LR,UC_ARM_REG_CPSR,UC_ARM_REG_SPSR]],bytes(u.mem_read(0x800feff8 if name!='ready' else 0x800ff000,8)),bytes(u.mem_read(0x80002000,64))))
 assert out[0]==out[1],(name,mode,flags,callback,thumb);cases+=1
print('PASS',cases,'CIdle Start/RunL entry-state cases, USER/range guards, ARM/Thumb callers, all GPR/CPSR/SPSR/SP/LR/live stack/object preserved. Native print ABI spied; original function remainder not simulated.')
