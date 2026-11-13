"""Compare actual DOS ordinal24 wrapper before/after the observation call."""
from pathlib import Path
import json,struct
from unicorn import Uc,UC_ARCH_ARM,UC_MODE_ARM,UC_HOOK_CODE
from unicorn.arm_const import *
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/firmware-overlays/dos-trace'
plan=json.loads((OUT/'trace.json').read_text());rom=(ROOT/'firmware/SYM.ROM').read_bytes()
regs=[UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3,UC_ARM_REG_R4,UC_ARM_REG_R5,UC_ARM_REG_R6,UC_ARM_REG_R7,UC_ARM_REG_R8,UC_ARM_REG_R9,UC_ARM_REG_R10,UC_ARM_REG_R11,UC_ARM_REG_SP,UC_ARM_REG_LR,UC_ARM_REG_CPSR]
def run(value,patched,entry,event):
 u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x50000000,0x1400000);u.mem_write(0x50000000,rom);u.mem_map(0x400000,65536)
 u.mem_write(0x511b8000,(OUT/'trace.bin').read_bytes());old=struct.unpack_from('<I',rom,0xfc16c0)[0];assert old==0xf97cf000
 if patched:
  for off,old,new in plan['records']:
   if off in plan['hooks']:u.mem_write(0x50000000+off,struct.pack('<I',new))
 u.reg_write(UC_ARM_REG_CPSR,0x80000010);u.reg_write(UC_ARM_REG_SP,0x40f000);u.reg_write(UC_ARM_REG_LR,0x50000001);u.reg_write(UC_ARM_REG_R0,0x401000);u.reg_write(UC_ARM_REG_R1,value)
 for r,n in zip(regs[4:12],range(4,12)):u.reg_write(r,n)
 common=[];printed=[]
 def hook(u,a,n,d):
  if a==0x50000000:u.emu_stop()
  elif a==0x50fc19bc:
   common.append(([u.reg_read(r) for r in regs],struct.unpack('<I',u.mem_read(u.reg_read(UC_ARM_REG_R2),4))[0]));u.reg_write(UC_ARM_REG_R0,0);u.reg_write(UC_ARM_REG_PC,u.reg_read(UC_ARM_REG_LR))
  elif a==0x503b409c:
   h,p=struct.unpack('<II',u.mem_read(u.reg_read(UC_ARM_REG_R0),8));assert bytes(u.mem_read(p,(h&0xfffffff)*2)).decode('utf-16le')=='D EVENT id=%08x value=%08x';printed.append((u.reg_read(UC_ARM_REG_R1),u.reg_read(UC_ARM_REG_R2)));lr=u.reg_read(UC_ARM_REG_LR)
   for r in regs[:4]+[UC_ARM_REG_R12]:u.reg_write(r,0xdeadbeef)
   u.reg_write(UC_ARM_REG_CPSR,0x60000010);u.reg_write(UC_ARM_REG_PC,lr)
 u.hook_add(UC_HOOK_CODE,hook);u.emu_start(entry,0,count=3000)
 assert u.reg_read(UC_ARM_REG_PC)==0x50000000 and u.reg_read(UC_ARM_REG_SP)==0x40f000
 assert len(common)==1 and common[0][0][1]==event and common[0][0][3]==4
 assert common[0][1]==value and printed==([(event,value)] if patched else [])
 return common
for entry,event in ((0x50fc16b5,1),(0x50fc1951,256)):
 for value in (0,1,2,3,12,255):assert run(value,False,entry,event)==run(value,True,entry,event)
print('PASS DOS selftest observer: actual native ordinal24 frame/event, original arguments/flags/SP/return, exact status output, no changed event values')
