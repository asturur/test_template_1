from pathlib import Path
import json,struct
from unicorn import Uc,UC_ARCH_ARM,UC_MODE_ARM,UC_HOOK_CODE
from unicorn.arm_const import *
rom=Path('firmware/SYM.ROM').read_bytes()
def run(scale):
 u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x50000000,0x1400000);u.mem_write(0x50000000,rom);u.mem_map(0x100000,0x10000)
 if scale==8:
  u.mem_write(0x5063ea2a,bytes.fromhex('c100'));u.mem_write(0x5063ea3c,bytes.fromhex('c100'))
 u.reg_write(UC_ARM_REG_SP,0x10f000);u.reg_write(UC_ARM_REG_R5,0x102000);u.reg_write(UC_ARM_REG_R6,0x103000);u.mem_write(0x102000,struct.pack('<I',0x104000));u.mem_write(0x103004,struct.pack('<I',0x105000));seen=[];res=[]
 def hook(u,a,s,d):
  if a==0x5063ea44:u.emu_stop()
  elif a==0x50640bc0:
   rid=u.reg_read(UC_ARM_REG_R0);assert u.reg_read(UC_ARM_REG_R1)==0x105000 and u.reg_read(UC_ARM_REG_R2)==2
   assert rid in (0x19bd6012,0x19bd6013);res.append(rid);u.reg_write(UC_ARM_REG_R0,20000000 if rid==0x19bd6012 else 2000000);u.reg_write(UC_ARM_REG_PC,u.reg_read(UC_ARM_REG_LR))
  elif a in (0x50640980,0x5064098c):
   seen.append((a,u.reg_read(UC_ARM_REG_R0),u.reg_read(UC_ARM_REG_R1)));u.reg_write(UC_ARM_REG_PC,u.reg_read(UC_ARM_REG_LR))
 u.hook_add(UC_HOOK_CODE,hook);u.emu_start(0x5063ea21,0,count=200)
 assert u.reg_read(UC_ARM_REG_PC)==0x5063ea44 and res==[0x19bd6012,0x19bd6013]
 assert seen==[(0x50640980,0x104000,20000000*scale),(0x5064098c,0x104000,2000000*scale)]
 return [v[2] for v in seen]
print(json.dumps({'original_server_client_us':run(1),'extended_server_client_us':run(8),'limits':'Original EikSrv Thumb configuration code executed; resource-reader and IPC leaf calls stubbed. Hardware outcome unverified.'},indent=2))
