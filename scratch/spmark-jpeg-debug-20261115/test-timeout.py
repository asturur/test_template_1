from pathlib import Path
import struct,json,hashlib
from unicorn import Uc,UC_ARCH_ARM,UC_MODE_ARM,UC_HOOK_CODE
from unicorn.arm_const import *
p=Path(__file__).resolve().parent
app=Path('scratch/spmark-benchmark-20261114/files/System/Apps/SPMark/SPMark.app').read_bytes();h=struct.unpack('<31I',app[:124]);rom=Path('build/firmware/nem4-factory/core.bin').read_bytes();base=h[19];co=h[25]
registers=[UC_ARM_REG_R4+i for i in range(8)]
results=[]
for expired in (False,True):
 for error in (0,-1,-4,-33):
  u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(base,0x20000);u.mem_write(base,app[co:]);u.mem_map(0x50000000,0x1400000);u.mem_write(0x50000000,rom);u.mem_map(0x20000000,0x100000)
  obj=0x20001000;sp=0x200ff000;stop=0x20000000;calls=[]
  u.mem_write(obj,struct.pack('<I',0x100106d4));u.mem_write(obj+8,struct.pack('<I',0 if expired else 1));u.mem_write(obj+0x30,b'\0'*4)
  def hook(c,a,n,d):
   if a==stop:c.emu_stop();return
   if a==0x1000d1a8:c.reg_write(UC_ARM_REG_PC,0x50399b90);return
   label={0x1000d3b8:'RTimer.Close',0x1000d3c8:'RTimer.Cancel',0x1000d258:'Scheduler.Stop',0x503b2470:'WaitForRequest'}.get(a)
   if label:
    calls.append(label);c.reg_write(UC_ARM_REG_R0,0);c.reg_write(UC_ARM_REG_PC,c.reg_read(UC_ARM_REG_LR))
  u.hook_add(UC_HOOK_CODE,hook)
  def invoke(entry,r1=0):
   u.reg_write(UC_ARM_REG_CPSR,0x10);u.reg_write(UC_ARM_REG_SP,sp);u.reg_write(UC_ARM_REG_LR,stop);u.reg_write(UC_ARM_REG_R0,obj);u.reg_write(UC_ARM_REG_R1,r1&0xffffffff)
   for i,r in enumerate(registers):u.reg_write(r,0xabc00000+i)
   u.emu_start(entry,0,count=300)
   assert u.reg_read(UC_ARM_REG_PC)==stop and u.reg_read(UC_ARM_REG_SP)==sp
   assert [u.reg_read(r) for r in registers]==[0xabc00000+i for i in range(len(registers))]
  # Model only scheduler dispatch's cleared iActive; handler and CActive::Cancel
  # execute original bytes. Timer/kernel services are spies, no real time modeled.
  if expired:invoke(0x10002bf4)
  invoke(0x10002fcc,error)
  expected=0 if expired else 1
  assert calls.count('Scheduler.Stop')==expected,(expired,error,calls)
  assert struct.unpack('<I',u.mem_read(obj+8,4))[0]==0
  assert struct.unpack('<I',u.mem_read(obj+0x30,4))[0]==(error&0xffffffff)
  results.append(dict(timer_dispatched_before_callback=expired,callback_error=error,calls=calls,scheduler_stop_count=expected))
r=dict(scope='Original SPMark timer RunL/ConvertComplete and original EUSER CActive::Cancel; RTimer Cancel/Close, scheduler Stop and WaitForRequest spied; dispatch inactive state modeled; does not prove actual board callback ordering',app_sha256=hashlib.sha256(app).hexdigest(),rom_sha256=hashlib.sha256(rom).hexdigest(),cases=results,status='PASS')
(p/'timeout-reproduction.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))
