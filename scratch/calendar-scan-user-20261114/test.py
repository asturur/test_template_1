from pathlib import Path
import struct,itertools
from unicorn import *
from unicorn.arm_const import *
p=Path('scratch/calendar-scan-user-20261114');rom=Path('build/firmware/nem4-factory/core.bin').read_bytes();blob=(p/'trace.bin').read_bytes();symbols={a[2]:int(a[0],16) for l in (p/'symbols.txt').read_text().splitlines() if len(a:=l.split())==3};cases=0
assert len(blob)<=4096
for name,entry,frame,saved in [('scan',0x505598a4,68,32)]:
 for mode,flags,point,arg3 in itertools.product([0x10],[0,0x60000000,0x90000000],[(0,0),(0,32),(1,0),(0,7)],[0,176,0x7fffffff]):
  out=[]
  for traced in [False,True]:
   u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x50000000,0x1400000);u.mem_write(0x50000000,rom);u.mem_write(0x511b8000,blob);u.mem_map(0x59000000,4096);u.mem_map(0x80000000,0x100000)
   u.mem_write(0x8000201c,struct.pack('<II',176,208));u.mem_write(0x8000202c,struct.pack('<II',8,1));u.mem_write(0x800ff00c,struct.pack('<I',0x80005000));u.mem_write(0x80003000,struct.pack('<ii',*point));vals=[0x100+i for i in range(13)];vals[:4]=[0x80002000,0x80004000,0x80003000,arg3];regs=[UC_ARM_REG_R0+i for i in range(13)];text=[]
   def code(c,a,n,d):
    if a==entry+12:c.emu_stop();return
    if a==0x503b409c:
     desc=c.reg_read(UC_ARM_REG_R0);length,addr=struct.unpack('<II',c.mem_read(desc,8));fmt=bytes(c.mem_read(addr,(length&0xfffffff)*2)).decode('utf-16-le');text.append((fmt,tuple(c.reg_read(r) for r in regs[1:4])))
     for r in regs[:4]+[UC_ARM_REG_R12]:c.reg_write(r,0x55555555)
     c.reg_write(UC_ARM_REG_CPSR,(c.reg_read(UC_ARM_REG_CPSR)&0x0fffffff)|0xa0000000)
     c.reg_write(UC_ARM_REG_PC,c.reg_read(UC_ARM_REG_LR))
   def write(c,access,addr,size,value,data):
    if addr==0x59000000:assert size==1;text.append(value&255)
   u.hook_add(UC_HOOK_CODE,code);u.hook_add(UC_HOOK_MEM_WRITE,write);u.reg_write(UC_ARM_REG_CPSR,mode|flags|0x20);u.reg_write(UC_ARM_REG_SPSR,0x90000010);u.reg_write(UC_ARM_REG_SP,0x800ff000);u.reg_write(UC_ARM_REG_LR,0x80000001)
   for r,v in zip(regs,vals):u.reg_write(r,v)
   if traced:u.mem_write(entry,bytes.fromhex('08b4014b1847c046')+struct.pack('<I',symbols[name+'_trace']))
   u.emu_start(entry|1,0,count=10000);assert u.reg_read(UC_ARM_REG_PC)==entry+12
   assert u.reg_read(UC_ARM_REG_SP)==0x800ff000-frame
   logged=(point[1]&31)==0 and (name!='pixel' or point[0]==0)
   assert bool(text)==bool(traced and logged)
   if text:assert text==[('B SCAN width=%08x height=%08x depth=%08x',(176,208,8)),('B POINT x=%08x y=%08x caller=%08x',(*point,0x80000001)),('B META colour=%08x compression=%08x length=%08x',(1,0,arg3))]
   out.append(([u.reg_read(r) for r in regs]+[u.reg_read(UC_ARM_REG_SP),u.reg_read(UC_ARM_REG_LR),u.reg_read(UC_ARM_REG_CPSR),u.reg_read(UC_ARM_REG_SPSR)],bytes(u.mem_read(0x800ff000-saved,saved)),bytes(u.mem_read(0x80002000,0x3000))))
  assert out[0]==out[1],(name,mode,flags,point,arg3);cases+=1
print('PASS',cases,'Thumb entry/replayed-prologue cases: all GPR/CPSR/SPSR/SP/LR and live saved stack/data match at exact original continuation; filtered metadata exact; native debug_print ABI spied, not executed. Rest of native function not simulated by this fixture.')
