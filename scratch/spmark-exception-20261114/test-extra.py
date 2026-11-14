from pathlib import Path
from unicorn import *
from unicorn.arm_const import *
import struct,random,itertools
p=Path(__file__).parent;rom=Path('build/firmware/nem4-factory/core.bin').read_bytes();blob=(p/'trace.bin').read_bytes();syms={a[2]:int(a[0],16) for l in (p/'symbols.txt').read_text().splitlines() if len(a:=l.split())==3};regs=[UC_ARM_REG_R0+i for i in range(13)];rnd=random.Random(68);cases=0
for mode,flags,stack_addr,pc in itertools.product([0x13,0x17,0x1b,0x1f],[0,0x20000000,0x60000000,0x90000000],[0x0040480c,0x00404fc0,0x003ff000],[0x503a6b78,0x503a6b34]):
 vals=[rnd.getrandbits(32) for _ in regs];vals[4]=5;vals[5]=0x80003000;vals[7]=0x80004000;sp=0x800ff000;frame=struct.pack('<17I',*[rnd.getrandbits(32) for _ in range(17)]);nums=list(struct.unpack('<17I',frame));nums[13]=stack_addr;nums[15]=pc;frame=struct.pack('<17I',*nums);details=struct.pack('<3I',0xffed0010,0,5);userstack=struct.pack('<32I',*range(32));outputs=[]
 for traced in [False,True]:
  u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x50000000,0x1400000);u.mem_write(0x50000000,rom);u.mem_write(0x511b8000,blob);u.mem_map(0x80000000,0x100000);u.mem_map(0x59000000,4096);u.mem_map(0x00400000,0x10000);u.mem_write(0x0040480c,userstack);u.mem_write(0x80003000,frame);u.mem_write(0x80004000,details);u.reg_write(UC_ARM_REG_CPSR,flags|mode);u.reg_write(UC_ARM_REG_SPSR,0x60000030);u.reg_write(UC_ARM_REG_SP,sp);u.reg_write(UC_ARM_REG_LR,0x503281a0)
  for r,v in zip(regs,vals):u.reg_write(r,v)
  output=[]
  def code(c,a,n,d):
   if a==0x5032cd24:c.emu_stop()
  def write(c,access,a,size,value,d):
   if a==0x59000000:assert size==1;output.append(value)
   else:assert sp-96<=a<sp,'Unexpected non-stack guest mutation'
  u.hook_add(UC_HOOK_CODE,code);u.hook_add(UC_HOOK_MEM_WRITE,write);u.emu_start(syms['fatal_entry'] if traced else 0x5032cd20,0,count=20000);assert u.reg_read(UC_ARM_REG_PC)==0x5032cd24
  nums=list(struct.unpack('<17I',frame));expected=bytes([0xc0])+b'S FATAL '+''.join(f'{x:08x} ' for x in [5,nums[15],nums[16],0xffed0010,0,5,*nums[:15]]).encode()+b'\n'
  expected+=bytes([0xc0])+b'S CP15 00000000 00000000 00000000\n'
  if pc==0x503a6b78 and stack_addr==0x0040480c:expected+=bytes([0xc0])+b'S STACK 0040480c '+''.join(f'{x:08x} ' for x in range(32)).encode()+b'\n'
  assert bytes(output)==(expected if traced else b'')
  outputs.append([u.reg_read(r) for r in regs]+[u.reg_read(UC_ARM_REG_SP),u.reg_read(UC_ARM_REG_LR),u.reg_read(UC_ARM_REG_CPSR),u.reg_read(UC_ARM_REG_SPSR)]+[bytes(u.mem_read(0x80003000,len(frame))),bytes(u.mem_read(0x80004000,12)),bytes(u.mem_read(0x0040480c,128))])
 assert outputs[0]==outputs[1];cases+=1
# Exact lookup return and its native pop; mapped own-DLL IAT read only.
for caller,fn in itertools.product([0xfff02920,0x50500000],[0,0xffe00074]):
 outputs=[]
 for traced in [False,True]:
  u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x50000000,0x1400000);u.mem_write(0x50000000,rom);u.mem_write(0x511b8000,blob);u.mem_map(0x80000000,0x100000);u.mem_map(0xffe00000,0x100000);u.mem_write(0xffeeb3a0,struct.pack('<I',0xffdc5367));u.mem_write(0x800ff000,struct.pack('<3I',4,5,caller));u.reg_write(UC_ARM_REG_CPSR,0x90000010);u.reg_write(UC_ARM_REG_SP,0x800ff000);u.reg_write(UC_ARM_REG_LR,0x12345678)
  for r,v in zip(regs,[fn,*range(1,13)]):u.reg_write(r,v)
  logs=[]
  def code(c,a,n,d):
   if a==0x503b2520:c.emu_stop();return
   if a==0x503b409c:
    logs.append(tuple(c.reg_read(r) for r in regs[1:4]));
    for r in regs[:4]+[UC_ARM_REG_R12]:c.reg_write(r,0x55555555)
    c.reg_write(UC_ARM_REG_CPSR,0x20000010);c.reg_write(UC_ARM_REG_PC,c.reg_read(UC_ARM_REG_LR))
  u.hook_add(UC_HOOK_CODE,code);u.emu_start(syms['lookup_return'] if traced else 0x503b251c,0,count=3000);assert u.reg_read(UC_ARM_REG_PC)==0x503b2520
  assert logs==([(fn,0xffdc5367 if fn else 0,caller)] if traced and caller==0xfff02920 else [])
  outputs.append([u.reg_read(r) for r in regs]+[u.reg_read(UC_ARM_REG_SP),u.reg_read(UC_ARM_REG_LR),u.reg_read(UC_ARM_REG_CPSR)])
 assert outputs[0]==outputs[1];cases+=1
print('PASS',cases,'fatal-kernel and user-lookup observer cases: exact log, complete GPR/flags/SPSR/stack continuation and read-only frame/IAT; no full native exception-policy or debug-service execution')
