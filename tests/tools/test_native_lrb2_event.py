"""Original CBUS/BTLDD GENIO callback contract, without an LRB2 model.

Actual kernel critical-section helpers and HAL MMIO execute. Only deferred work
queue delivery is spied. The fixture supplies status; this proves bit/ACK/queue
ownership, not reset/sync polarity, a radio response or working Bluetooth.
"""
from pathlib import Path
import hashlib,struct,json
from unicorn import *
from unicorn.arm_const import *
ROOT=Path(__file__).resolve().parents[2]
r=(ROOT/'build/firmware/nem4-factory/core.bin').read_bytes();assert hashlib.sha256(r).hexdigest()=='be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524'
results=[]
for status in (0,1,0x10,0x90):
 for flags in (0,0x60000000,0xa0000000):
  u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x50000000,0x1400000);u.mem_write(0x50000000,r)
  u.mem_map(0x80000000,0x20000);u.mem_map(0x58000000,0x200000)
  stop,cbus,callback,bt=0x80000000,0x80001000,0x80002000,0x80003000
  u.mem_write(cbus+0x164,struct.pack('<I',callback));u.mem_write(callback,struct.pack('<II',0x503f1298,bt));u.mem_write(0x58150102,struct.pack('<H',status))
  queued=[];reads=[];writes=[]
  def code(c,a,n,d):
   if a==stop:c.emu_stop()
   elif a==0x503f2a7c:
    queued.append(c.reg_read(UC_ARM_REG_R0));c.reg_write(UC_ARM_REG_PC,c.reg_read(UC_ARM_REG_LR))
  def access(c,k,a,n,v,d):
   if k==UC_MEM_WRITE:writes.append((hex(a),n,v))
   else:reads.append((hex(a),n))
  u.hook_add(UC_HOOK_CODE,code);u.hook_add(UC_HOOK_MEM_READ|UC_HOOK_MEM_WRITE,access,begin=0x58000000,end=0x581fffff)
  u.reg_write(UC_ARM_REG_CPSR,flags|0x13);u.reg_write(UC_ARM_REG_SP,0x8001f000);u.reg_write(UC_ARM_REG_LR,stop);u.reg_write(UC_ARM_REG_R0,cbus)
  try:u.emu_start(0x503825ec,0,count=2000)
  except UcError:
   print('failure PC',hex(u.reg_read(UC_ARM_REG_PC)), 'access',reads,writes);raise
  assert u.reg_read(UC_ARM_REG_PC)==stop,hex(u.reg_read(UC_ARM_REG_PC))
  assert u.reg_read(UC_ARM_REG_SP)==0x8001f000
  assert reads==[('0x58150102',2)],reads
  assert writes==([('0x58150102',2,0x10)] if status&0x10 else []),writes
  assert queued==([bt+0x147c] if status&0x10 else []),queued
  assert struct.unpack('<I',u.mem_read(bt+0x1578,4))[0]==bool(status&0x10)
  assert bytes(u.mem_read(0x50000000,len(r)))==r
  results.append(dict(status=status,reads=reads,writes=writes,queued=queued))
output=ROOT/'build/sim/unit-native-lrb2-event'
output.mkdir(parents=True,exist_ok=True)
(output/'result.json').write_text(json.dumps(dict(scope='Original CBUS and BTLDD GENIO20 callback; only deferred queue delivery spied',cases=results),indent=2)+'\n')
print('PASS 12 original CBUS/BTLDD event cases:150102 bit10 -> original W1C and deferred work, unrelated silence, SP and ROM unchanged')
