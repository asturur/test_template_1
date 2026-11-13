from pathlib import Path
from unicorn import *
from unicorn.arm_const import *
b=Path('scratch/rf-board-qualification-20261113/assert/trace.bin').read_bytes();assert len(b)<0x300
regs=[UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3,UC_ARM_REG_R4,UC_ARM_REG_R5,UC_ARM_REG_R6,UC_ARM_REG_R7,UC_ARM_REG_R8,UC_ARM_REG_R9,UC_ARM_REG_R10,UC_ARM_REG_R11,UC_ARM_REG_SP,UC_ARM_REG_LR]
for valid,length in ((True,7),(True,200),(False,0)):
 u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x51716000,4096);u.mem_write(0x51716d00,b);u.mem_map(0x516c0000,0x10000);u.mem_map(0x514a2000,4096);u.mem_map(0x80000000,65536);u.mem_map(0x59000000,4096);u.mem_map(0x80020000,65536);u.mem_write(0x80024388,bytes(range(24)))
 file,expr=(0x516c96f0,0x516c9800) if valid else (0x80010000,0)
 if valid:u.mem_write(file,b'Fiqueue.c\0');u.mem_write(expr,b'X'*length+b'\0')
 values=[file,123,expr,3,4,5,6,7,8,9,10,11,0x8000f000,0x516c1235]
 u.reg_write(UC_ARM_REG_CPSR,0xa000001b)
 for r,v in zip(regs,values):u.reg_write(r,v)
 out=[]
 def write(c,a,addr,n,v,d):
  if addr==0x59000000:assert n==1;out.append(v)
  else:assert 0x8000efc0<=addr<0x8000f000
 def code(c,addr,n,d):
  if addr==0x514a2804:c.emu_stop()
 u.hook_add(UC_HOOK_MEM_WRITE,write);u.hook_add(UC_HOOK_CODE,code);u.emu_start(0x51716d00,0,count=8000)
 assert u.reg_read(UC_ARM_REG_PC)==0x514a2804
 assert u.reg_read(UC_ARM_REG_CPSR)&0xf000003f==0xa000001b
 for r,v in zip(regs,values):assert u.reg_read(r)==v
 expected=f'A NOS file/line/expr/lr {file:08x} 0000007b {expr:08x} 516c1235 '+('Fiqueue.c' if valid else '')+' '+('X'*min(length,160) if valid else '')+'\n'
 expected+='A RESULTS '+''.join(f'{int.from_bytes(bytes(range(i,i+4)),"little"):08x} ' for i in range(0,24,4))+'\n'
 assert bytes(out)==expected.encode(),bytes(out)
 assert bytes(u.mem_read(0x80024388,24))==bytes(range(24))
print('PASS native NOS assertion observer: original args/registers/flags/SP/ARM tail, bounded ROM strings and invalid pointers, stack/debug-only writes')
