#!/usr/bin/env python3
"""Run the original firmware's class-table validation in Unicorn, with synthetic RAM."""
from pathlib import Path
import hashlib, json, struct
from unicorn import Uc, UC_ARCH_ARM, UC_MODE_ARM, UC_HOOK_CODE
from unicorn.arm_const import UC_ARM_REG_R0, UC_ARM_REG_SP, UC_ARM_REG_LR
root=Path(__file__).resolve().parents[2]
rom=(root/'firmware/SYM.ROM').read_bytes()
ROM_BASE=0x50349000; ROM_OFF=0x349000; RAM=0x80000000

def run(classes):
 u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(ROM_BASE,0x2000);u.mem_write(ROM_BASE,rom[ROM_OFF:ROM_OFF+0x2000]);u.mem_map(RAM,0x10000)
 obj=RAM+0x1000; table=RAM+0x2000
 for i,v in enumerate(classes):u.mem_write(obj+0x40+i*4,struct.pack('<I',v))
 u.mem_write(obj+0x4c,struct.pack('<I',table));u.mem_write(obj+0x50,struct.pack('<I',len(classes)))
 u.reg_write(UC_ARM_REG_R0,obj);u.reg_write(UC_ARM_REG_SP,RAM+0xf000);u.reg_write(UC_ARM_REG_LR,0x50349688)
 outcome={'state':'timeout'}
 def hook(uc,address,size,user):
  if address==0x50349658:outcome['state']='variant_fault_19';uc.emu_stop()
  elif address==0x50349688:outcome['state']='table_accepted';uc.emu_stop()
 u.hook_add(UC_HOOK_CODE,hook);u.emu_start(0x5034933c,0,count=5000)
 return {'classes':classes,'outcome':outcome['state']}
results=[run(c) for c in ([0,4,0],[0,0,0],[4,4,4],[0,0,4],[4,0,4],[4,4,0],[0,4,4],[4,0,0])]
assert results[0]['outcome']=='variant_fault_19' and results[1]['outcome']=='table_accepted'
out={'note':'Synthetic RAM and stop-before-side-effects; real firmware instructions, no board emulation.','rom_sha256':hashlib.sha256(rom).hexdigest(),'results':results}
(root/'scratch/variant-class-test/results.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out,indent=2))
