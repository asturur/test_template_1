from pathlib import Path
from unicorn import *
from unicorn.arm_const import *
import struct,itertools,random
p=Path(__file__).parent;b=(p/'trace.bin').read_bytes();rom=Path('build/firmware/nem4-factory/core.bin').read_bytes();syms={a[2]:int(a[0],16) for l in (p/'symbols.txt').read_text().splitlines() if len(a:=l.split())==3};rnd=random.Random(911);count=0
regs=[UC_ARM_REG_R0+i for i in range(13)]
for name,entry,end in [('load_return',0x503ac954,0x503ac958),('compare_entry',0x503a61c4,0x503a61c8)]:
 for fl,result,caller,other in itertools.product([0,0x60000000,0x90000000,0xf0000000],[0,1,0xffffffff],[0x100029fc,0x5000a000,0x9000,0xfff029fc,0xfff028d8],[0,1]):
  outputs=[]
  vals=[rnd.getrandbits(32) for _ in regs];vals[0]=result;vals[2]=other;vals[3]=0;vals[4]=0x28000;vals[5]=0x80002000;vals[6]=0x80003000;sp=0x800ff000
  for traced in [False,True]:
   u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x50000000,0x1400000);u.mem_write(0x50000000,rom);u.mem_write(0x511b8000,b);u.mem_map(0x80000000,0x100000);u.mem_write(0x80002000,struct.pack('<I',0x123));u.mem_write(0x80003000,struct.pack('<II',0x1000000a,0x80003100));u.mem_write(0x80003100,'3dtest.dll'.encode('utf-16-le'));stack=bytes([0xa5])*96;u.mem_write(sp,stack);u.mem_write(sp+4,struct.pack('<I',caller));u.mem_write(sp+28,struct.pack('<I',caller));u.reg_write(UC_ARM_REG_CPSR,fl|0x10);u.reg_write(UC_ARM_REG_SP,sp);u.reg_write(UC_ARM_REG_LR,caller)
   for r,v in zip(regs,vals):u.reg_write(r,v)
   logs=[]
   def hook(c,a,n,d):
    if a==end:c.emu_stop();return
    if a==0x503b409c:
     desc=c.reg_read(UC_ARM_REG_R0);length,addr=struct.unpack('<II',c.mem_read(desc,8));fmt=bytes(c.mem_read(addr,(length&0xfffffff)*2)).decode('utf-16le');args=tuple(c.reg_read(r) for r in regs[1:4]);logs.append((fmt,args))
     for r in regs[:4]+[UC_ARM_REG_R12]:c.reg_write(r,0x55555555)
     c.reg_write(UC_ARM_REG_CPSR,0xa0000010);c.reg_write(UC_ARM_REG_PC,c.reg_read(UC_ARM_REG_LR))
   u.hook_add(UC_HOOK_CODE,hook)
   u.emu_start(syms[name] if traced else entry,0,count=2000);assert u.reg_read(UC_ARM_REG_PC)==end
   logged=(name=='load_return' and caller==0xfff028d8) or (name=='compare_entry' and caller==0xfff029fc)
   assert bool(logs)==(traced and logged),(name,result,logs)
   if traced and name=='load_return' and logged:assert logs[0]==('S LOAD code=%08x handle=%08x caller=%08x',(result,0x123,caller)) and logs[1][1][0]==0x80003000
   if traced and name=='alloc_return' and result==0:assert logs==[('S ALLOCFAIL bytes=%08x result=%08x caller=%08x',(0x28000,0,caller))]
   if traced and name=='null_entry' and result==0:assert logs==[('S NULL caller=%08x r4=%08x r5=%08x',(caller,0x28000,0x80002000))]
   if traced and name=='compare_entry' and logged:assert logs==[('S CMP0 lo=%08x hi=%08x caller=%08x',(result,vals[1],caller))]
   outputs.append([u.reg_read(r) for r in regs]+[u.reg_read(UC_ARM_REG_SP),u.reg_read(UC_ARM_REG_LR),u.reg_read(UC_ARM_REG_CPSR)]+[bytes(u.mem_read(sp-8 if name=='null_entry' else sp-4 if name=='compare_entry' else sp,104))])
  assert outputs[0]==outputs[1],(name,result,caller,outputs);count+=1
print('PASS',count,'native USER observer state/log/replay cases; RDebug ABI spied, full firmware service not simulated')
