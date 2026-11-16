"""Check terminal-only abort logging; normal vector handoffs stay transparent."""
from pathlib import Path
import struct,json,sys
from unicorn import Uc, UC_ARCH_ARM, UC_MODE_ARM, UC_HOOK_CODE, UC_HOOK_MEM_WRITE
from unicorn.arm_const import *
ROOT=Path(__file__).resolve().parents[3]
out=ROOT/(sys.argv[1] if len(sys.argv)>1 else 'build/diagnostics/block-fusion-abort-observer-20261116')
blob=(out/'observer.bin').read_bytes()
first_abort=json.loads((out/'manifest.json').read_text()).get('first_abort_breakpoint',False)
regs=[UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3,UC_ARM_REG_R4,UC_ARM_REG_R5,UC_ARM_REG_R6,UC_ARM_REG_R7,UC_ARM_REG_R8,UC_ARM_REG_R9,UC_ARM_REG_R10,UC_ARM_REG_R11,UC_ARM_REG_R12,UC_ARM_REG_SP,UC_ARM_REG_LR]
count=0
for kind,entry,normal in [(1,0x20,0x608),(2,0x30,0x5f8)]:
 for mmu in [0,1]:
  for lr in [0x104,0xa077ffc,0x50384d60,0xfff00004]:
   for flags in [0,0x10000000,0xe0000000,0xf0000000]:
    for spsr in [0xd3,0xdb,0x600000d2]:
     u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0,0x1000);u.mem_write(0x20,blob)
     for base in [0x0c004000,0x58004000]:u.mem_map(base,0x1000)
     cpsr=flags|0xd7;u.reg_write(UC_ARM_REG_CPSR,cpsr);u.reg_write(UC_ARM_REG_SPSR,spsr)
     initial=[0xabc00000+i*0x101 for i in range(15)];initial[-1]=lr
     for r,v in zip(regs,initial):u.reg_write(r,v)
     writes=[];cp=[];end=[];far=0x0a077fe8;fsr=0x0d
     def code(uc,pc,size,_):
      if pc in [0x608,0x5f8,0x60c]:end.append(pc);uc.emu_stop();return
      if pc in [0x40,0x54,0x5c]:
       reg,value={0x40:(UC_ARM_REG_R0,0x78|mmu),0x54:(UC_ARM_REG_R1,far),0x5c:(UC_ARM_REG_R1,fsr)}[pc]
       cp.append(pc);uc.reg_write(reg,value);uc.reg_write(UC_ARM_REG_PC,pc+4)
     u.hook_add(UC_HOOK_CODE,code)
     u.hook_add(UC_HOOK_MEM_WRITE,lambda uc,access,address,size,value,user:writes.append((address,size,value)))
     u.emu_start(entry,0x1000,count=100)
     high=bool(lr&0x50000000) and not first_abort
     assert end==[normal if high else 0x60c],end
     result=lr&0x50000000
     expected_flags=(cpsr&~0xe0000000)|(0 if result else 0x40000000)
     assert u.reg_read(UC_ARM_REG_CPSR)==expected_flags
     assert u.reg_read(UC_ARM_REG_SPSR)==spsr
     final=[u.reg_read(r) for r in regs]
     if high:
      assert final==initial and not writes and not cp
     else:
      dest=0x580047f0 if mmu else 0x0c0047f0
      assert writes==[(dest,4,lr),(dest+4,4,far),(dest+8,4,fsr|(kind<<16)|((spsr&255)<<24))],writes
      assert final[4:]==initial[4:]
      assert cp==[0x40,0x54,0x5c]
     count+=1
mode = 'first-abort breakpoint' if first_abort else 'terminal logging and native handoffs'
print(f'PASS {count} abort cases: {mode}, flags, SPSR, stack and LR; CP15 reads spied')
