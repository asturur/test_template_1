"""Bounded original-register fixture for the guarded Nokia.dsy dump."""
from pathlib import Path
import struct,subprocess,json
from unicorn import Uc,UC_ARCH_ARM,UC_MODE_ARM,UC_HOOK_CODE,UC_HOOK_MEM_READ
from unicorn.arm_const import *
root=Path(__file__).resolve().parents[2]
blob=(root/'build/firmware-overlays/exit-trace/trace.bin').read_bytes()
symbols={p[2]:int(p[0],16) for line in subprocess.check_output(['arm-none-eabi-nm',str(root/'build/firmware-overlays/exit-trace/trace.elf')],text=True).splitlines() if len(p:=line.split())==3}
def run(caller=0x50fc9a7b,length=12,pointer=0x403418):
 u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x50000000,0x1400000);u.mem_write(0x511b6000,blob);u.mem_map(0x400000,0x10000)
 u.reg_write(UC_ARM_REG_CPSR,0x80000010)
 values={UC_ARM_REG_R0:pointer,UC_ARM_REG_R1:25,UC_ARM_REG_R2:0x6000000a,UC_ARM_REG_R3:length,UC_ARM_REG_R6:0x4030ac,UC_ARM_REG_R12:0x12345678,UC_ARM_REG_LR:caller,UC_ARM_REG_SP:0x401e04}
 for reg,value in values.items():u.reg_write(reg,value)
 u.mem_write(0x401e04,struct.pack('<I',0x5060dead));u.mem_write(0x403418,bytes(range(12)))
 prints=[];reads=[]
 def read(u,access,address,size,value,data):
  if 0x403418<=address<0x403424:reads.append((address,size))
 def hook(u,address,size,data):
  if address==0x503b1b78:u.emu_stop()
  elif address==0x503b409c:
   desc=u.reg_read(UC_ARM_REG_R0);header,ptr=struct.unpack('<II',u.mem_read(desc,8));text=bytes(u.mem_read(ptr,(header&0xfffffff)*2)).decode('utf-16le')
   prints.append((text,[u.reg_read(r) for r in (UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3)],int.from_bytes(u.mem_read(u.reg_read(UC_ARM_REG_SP),4),'little')))
   lr=u.reg_read(UC_ARM_REG_LR)
   for reg in (UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3,UC_ARM_REG_R12):u.reg_write(reg,0)
   u.reg_write(UC_ARM_REG_CPSR,0x60000010);u.reg_write(UC_ARM_REG_PC,lr)
 u.hook_add(UC_HOOK_CODE,hook);u.hook_add(UC_HOOK_MEM_READ,read);u.emu_start(symbols['trace_descriptor_bounds'],0,count=1000)
 assert u.reg_read(UC_ARM_REG_PC)==0x503b1b78
 assert all(u.reg_read(reg)==value for reg,value in values.items())
 assert u.reg_read(UC_ARM_REG_CPSR)&0xf0000000==0x80000000
 enabled=(caller==0x50fc9a7b and length==12 and 0x400000<=pointer<0xff0000)
 assert len(prints)==(2 if enabled else 1)
 if enabled:
  assert prints[1][0].startswith('X DSY_MESSAGE ')
  assert prints[1][1]==[0x03020100,0x07060504,0x0b0a0908] and prints[1][2]==0x5060dead
  assert reads==[(0x403418,4),(0x40341c,4),(0x403420,4)]
 else:assert not reads
run();run(caller=0x503abcde);run(length=11);run(pointer=0x1000);run(pointer=0x1000000)
print('PASS DSY dump: exact caller/length/address guards,12-byte payload/caller and register/flags/SP preservation')
