#!/usr/bin/env python3
"""Test firmware's early CS1/CS2 identification branch with synthetic flash IDs."""
from pathlib import Path
import hashlib,json,struct
from unicorn import Uc,UC_ARCH_ARM,UC_MODE_ARM,UC_HOOK_CODE,UC_HOOK_MEM_READ
from unicorn.arm_const import UC_ARM_REG_LR,UC_ARM_REG_R0,UC_ARM_REG_SP
r=Path(__file__).resolve().parents[2];rom=(r/'firmware/SYM.ROM').read_bytes()
def probe(cs1,cs2):
 u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0,0x10000);u.mem_write(0,rom[:0x10000]);u.mem_map(0x02000000,0x10000);u.mem_map(0x04000000,0x10000);u.reg_write(UC_ARM_REG_SP,0xf000);u.reg_write(UC_ARM_REG_LR,0x8000);done=[]
 def read(uc,access,address,size,value,user):
  base=address & 0xff000000
  if base in (0x02000000,0x04000000) and address-base in (0,2) and size==2:
   pair=cs1 if base==0x02000000 else cs2;v=pair[(address-base)//2];uc.mem_write(address,struct.pack('<H',v))
 def code(uc,address,size,user):
  if address==0x8000:done.append(uc.reg_read(UC_ARM_REG_R0));uc.emu_stop()
 u.hook_add(UC_HOOK_MEM_READ,read);u.hook_add(UC_HOOK_CODE,code);u.emu_start(0x95c,0,count=2000)
 if not done:raise RuntimeError('routine did not return')
 return {'cs1':[hex(x) for x in cs1],'cs2':[hex(x) for x in cs2],'probe_result':done[0]}
results=[probe((1,x),(1,0x227e)) for x in (0x227e,0x257e,0x22d1)]
assert [x['probe_result'] for x in results]==[0,2,1],results
out={'rom_sha256':hashlib.sha256(rom).hexdigest(),'note':'Firmware routine and synthetic IDs; no hardware or bank-layout validation','results':results};(r/'scratch/flash-first-probe-test/results.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out,indent=2))
