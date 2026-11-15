from pathlib import Path
import json,struct,random
from unicorn import Uc,UC_ARCH_ARM,UC_MODE_ARM,UC_HOOK_CODE
from unicorn.arm_const import *
p=Path(__file__).resolve().parent;manifest=json.loads((p/'observer-manifest.json').read_text());rom=Path('build/firmware/nem4-factory/core.bin').read_bytes();blob=(p/'trace.bin').read_bytes();syms={a[2]:int(a[0],16) for l in (p/'symbols.txt').read_text().splitlines() if len(a:=l.split())==3};regs=[UC_ARM_REG_R0+i for i in range(13)];rng=random.Random(1615);cases=0
for h in manifest['hooks']:
 for caller in h['callers']+[0x5000a000,0x10002ff4,0xfff12ff4]:
  for flags in (0,0x60000000,0x90000000,0xf0000000):
   for active in (0,1):
    vals=[rng.getrandbits(32) for _ in regs];obj=0x80002000;vals[0]=obj;sp=0x800ff000;outputs=[]
    for traced in (False,True):
     u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x50000000,0x1400000);u.mem_write(0x50000000,rom);u.mem_write(manifest['trace_base'],blob);u.mem_map(0x80000000,0x100000);u.mem_write(obj,struct.pack('<3I',0x12345678,0x80000001,active));u.mem_write(sp,b'\xa5'*96);u.reg_write(UC_ARM_REG_CPSR,flags|0x10);u.reg_write(UC_ARM_REG_SP,sp);u.reg_write(UC_ARM_REG_LR,caller)
     for r,v in zip(regs,vals):u.reg_write(r,v)
     logs=[]
     def hook(c,a,n,d):
      if a==h['address']+4:c.emu_stop();return
      if a==0x503b409c:
       desc=c.reg_read(UC_ARM_REG_R0);length,ptr=struct.unpack('<II',c.mem_read(desc,8));fmt=bytes(c.mem_read(ptr,(length&0xfffffff)*2)).decode('utf-16le');args=tuple(c.reg_read(r) for r in regs[1:4]);logs.append((fmt,args))
       for r in regs[:4]+[UC_ARM_REG_R12]:c.reg_write(r,0x55555555)
       c.reg_write(UC_ARM_REG_CPSR,0xa0000010);c.reg_write(UC_ARM_REG_PC,c.reg_read(UC_ARM_REG_LR))
     u.hook_add(UC_HOOK_CODE,hook);u.emu_start(syms['jpeg_'+h['name']] if traced else h['address'],0,count=500);assert u.reg_read(UC_ARM_REG_PC)==h['address']+4
     expected=traced and caller in h['callers'];assert bool(logs)==expected,(h['name'],caller,logs)
     if expected:
      value={'after':vals[2],'cancel':active,'close':0x12345678,'stop':vals[1]}[h['name']];assert logs==[(f'J {h["name"].upper()} obj=%08x value=%08x caller=%08x',(obj,value,caller))]
     frame={'after':16,'cancel':8,'close':4,'stop':8}[h['name']]
     outputs.append(([u.reg_read(r) for r in regs],u.reg_read(UC_ARM_REG_SP),u.reg_read(UC_ARM_REG_LR),u.reg_read(UC_ARM_REG_CPSR),bytes(u.mem_read(sp-frame,frame+96)),bytes(u.mem_read(obj,12))))
    assert outputs[0]==outputs[1],(h['name'],hex(caller));cases+=1
print('PASS',cases,'exact GPR/CPSR/SP/LR/live stack/object/log/filter/displaced-instruction cases; RDebug ABI spied, no board ordering claim')
(p/'observer-test-result.json').write_text(json.dumps(dict(status='PASS',cases=cases,scope='Exact state/stack/log/filter preservation; RDebug ABI spied; not hardware ordering'),indent=2)+'\n')
