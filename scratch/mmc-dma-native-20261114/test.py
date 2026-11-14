from pathlib import Path
from unicorn import Uc,UC_ARCH_ARM,UC_MODE_ARM,UC_HOOK_CODE,UC_HOOK_MEM_WRITE
from unicorn.arm_const import *
import random,struct,json
p=Path('scratch/mmc-dma-native-20261114');b=(p/'trace.bin').read_bytes();rnd=random.Random(1411);regs=[UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3,UC_ARM_REG_R4,UC_ARM_REG_R5,UC_ARM_REG_R6,UC_ARM_REG_R7,UC_ARM_REG_R8,UC_ARM_REG_R9,UC_ARM_REG_R10,UC_ARM_REG_R11,UC_ARM_REG_R12,UC_ARM_REG_LR]
syms=json.loads((p/'manifest.json').read_text())['hooks']
for name,entry,resume,changed in [('begin',0x511bd000,0x503f470c,3),('end',0x511bd054,0x503f5078,2),('error',0,0x503f5090,-1)]:
 for case in range(64):
  entry=int(syms['mmc_'+name],16)
  u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x59000000,4096);u.mem_map(0x50000000,0x1400000);u.mem_write(0x511bd000,b);u.mem_map(0x80000000,0x100000)
  flags=(rnd.randrange(16)<<28)|0x13;u.reg_write(UC_ARM_REG_CPSR,flags);sp=0x800ff000;u.reg_write(UC_ARM_REG_SP,sp)
  original=[rnd.getrandbits(32) for r in regs];original[0]=0 if name=='error' and case%2==0 else original[0];original[5]=0x80010000;original[6]=0x80020000
  for r,v in zip(regs,original):u.reg_write(r,v)
  obj=bytes(rnd.getrandbits(8) for _ in range(0x900));req=bytes(rnd.getrandbits(8) for _ in range(0x60));u.mem_write(original[5],obj);u.mem_write(original[6],req);calls=[]
  output=[]
  def hook(c,a,n,d):
   if a==resume:c.emu_stop()
  def write(c,access,a,size,value,data):
   if a==0x59000000:assert size==1;output.append(value)
  u.hook_add(UC_HOOK_CODE,hook);u.hook_add(UC_HOOK_MEM_WRITE,write);u.emu_start(entry,0,count=3000)
  word=lambda raw,off:struct.unpack_from('<I',raw,off)[0]
  expected=([word(req,4),word(req,8),word(req,0x14),word(req,0x2c),original[6],original[5],word(obj,0x8b4)] if name=='begin' else [word(req,4),word(obj,0x8c8),word(obj,0x8c4)]+[word(req,i) for i in range(0x48,0x58,4)])
  if name=='error':expected=[word(req,4),word(obj,0x8c8),original[0]]+[word(req,i) for i in range(0x48,0x58,4)]
  expect_bytes=bytes([0xc0])+('M '+{'begin':'B','end':'E','error':'X'}[name]+' '+''.join(f'{v:08x} ' for v in expected)+'\n').encode()
  if name=='error' and original[0]==0:expect_bytes=b''
  assert bytes(output)==expect_bytes,output
  assert u.reg_read(UC_ARM_REG_PC)==resume
  if changed>=0:original[changed]=(struct.unpack_from('<I',obj,0x8b8)[0] if name=='begin' else 0)
  assert [u.reg_read(r) for r in regs]==original
  assert u.reg_read(UC_ARM_REG_CPSR)==flags and u.reg_read(UC_ARM_REG_SP)==sp+(8 if name=='error' else 0)
  assert bytes(u.mem_read(0x80010000,len(obj)))==obj and bytes(u.mem_read(0x80020000,len(req)))==req
print('PASS 192 ARM direct-port observer ABI/flags/stack/output and displaced-instruction cases; actual byte-output instructions, original MMC behavior unmodified')
