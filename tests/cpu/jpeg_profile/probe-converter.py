from pathlib import Path
import struct,json
from unicorn import Uc,UC_ARCH_ARM,UC_MODE_ARM,UC_HOOK_CODE
from unicorn.arm_const import *
p=Path('build/sim/jpeg-profile');p.mkdir(parents=True,exist_ok=True);rom=Path('build/firmware/nem4-factory/core.bin').read_bytes();out=[]
for mode in (8,10):
 u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.ctl_set_cpu_model(UC_CPU_ARM_926);u.mem_map(0x50000000,0x1400000);u.mem_write(0x50000000,rom);u.mem_map(0x80000000,0x20000);heap=0x80002000;calls=[]
 def hook(c,a,n,d):
  if a==0x80000000:c.emu_stop();return
  if a in (0x505adf24,0x505adf78):
   calls.append((hex(a),c.reg_read(UC_ARM_REG_R0)));c.reg_write(UC_ARM_REG_R0,heap);c.reg_write(UC_ARM_REG_PC,c.reg_read(UC_ARM_REG_LR))
 u.hook_add(UC_HOOK_CODE,hook);u.reg_write(UC_ARM_REG_CPSR,0x10);u.reg_write(UC_ARM_REG_SP,0x8001f000);u.reg_write(UC_ARM_REG_R0,mode);u.reg_write(UC_ARM_REG_LR,0x80000000);u.emu_start(0x505a8471,0,count=1000);assert u.reg_read(UC_ARM_REG_PC)==0x80000000
 ptr=u.reg_read(UC_ARM_REG_R0);print('returned',hex(ptr),'calls',calls,flush=True);v=struct.unpack('<I',u.mem_read(ptr,4))[0];methods=struct.unpack('<4I',u.mem_read(v,16));out.append(dict(mode=mode,pointer=ptr,vtable=v,methods=list(methods),allocations=calls));print(mode,hex(v),list(map(hex,methods)),calls)
(p/'converter.json').write_text(json.dumps(out,indent=2)+'\n')
