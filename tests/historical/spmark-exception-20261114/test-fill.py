from pathlib import Path
from unicorn import *
from unicorn.arm_const import *
import itertools,struct,random
p=Path(__file__).parent;b=(p/'trace.bin').read_bytes();rom=Path('build/firmware/nem4-factory/core.bin').read_bytes();syms={a[2]:int(a[0],16) for l in (p/'symbols.txt').read_text().splitlines() if len(a:=l.split())==3};regs=[UC_ARM_REG_R0+i for i in range(13)];rnd=random.Random(44);count=0
for flags,caller,length in itertools.product([0,0x60000000,0x90000000],[0xffe01234,0xfff05678,0x503a1010],[0,63,64,65]):
 vals=[rnd.getrandbits(32) for _ in regs];vals[0]=0x00819dbc;vals[1]=0;vals[2]=length;outs=[]
 for traced in [False,True]:
  u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x50000000,0x1400000);u.mem_write(0x50000000,rom);u.mem_write(0x511b8000,b);u.mem_map(0x80000000,0x100000);u.reg_write(UC_ARM_REG_CPSR,flags|0x10);u.reg_write(UC_ARM_REG_SP,0x800ff000);u.reg_write(UC_ARM_REG_LR,caller)
  for r,v in zip(regs,vals):u.reg_write(r,v)
  text=[]
  def code(c,a,n,d):
   if a==0x503a31d8:c.emu_stop();return
   if a==0x503b409c:
    desc=c.reg_read(UC_ARM_REG_R0);size,ptr=struct.unpack('<II',c.mem_read(desc,8));fmt=bytes(c.mem_read(ptr,(size&0xfffffff)*2)).decode('utf-16le');text.append((fmt,tuple(c.reg_read(r) for r in regs[1:4])))
    for r in regs[:4]+[UC_ARM_REG_R12]:c.reg_write(r,0x55555555)
    c.reg_write(UC_ARM_REG_CPSR,0x20000010);c.reg_write(UC_ARM_REG_PC,c.reg_read(UC_ARM_REG_LR))
  u.hook_add(UC_HOOK_CODE,code);u.emu_start(syms['fill_entry'] if traced else 0x503a31d4,0,count=3000);assert u.reg_read(UC_ARM_REG_PC)==0x503a31d8
  assert text==([('S FILL dst=%08x len=%08x caller=%08x',(0x00819dbc,64,caller))] if traced and caller>=0xff000000 and length==64 else [])
  outs.append([u.reg_read(r) for r in regs]+[u.reg_read(UC_ARM_REG_SP),u.reg_read(UC_ARM_REG_LR),u.reg_read(UC_ARM_REG_CPSR)]+[bytes(u.mem_read(0x800feff8,8))])
 assert outs[0]==outs[1];count+=1
print('PASS',count,'native Fill entry state/stack/log/filter cases; debug service ABI spied')
