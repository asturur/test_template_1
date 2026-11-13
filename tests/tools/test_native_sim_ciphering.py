"""Original SIM ciphering request/cache getter/completion contract.

The fixture explicitly delivers the getter's original notification through
spied registration/consumption leaves. This proves native reply values and
ownership, not real scheduler delivery, serving SIM or physical initialization.
"""
from pathlib import Path
import struct,json,hashlib
from unicorn import *
from unicorn.arm_const import *
p=Path(__file__).resolve().parents[2];rom=(p/'firmware/THC N-Gage ROM Dump/ngage-gsmstuff-0x5149D280.dll').read_bytes()[96:];base=0x5149d280;reports=[]
assert hashlib.sha256((p/'firmware/THC N-Gage ROM Dump/ngage-gsmstuff-0x5149D280.dll').read_bytes()).hexdigest()=='e5870e918c90d9c7a6403eb0ee305d174e906aeae0a7fa8069e85a18aeec7aa1'
for valid,flag,result,status in ((False,0,0,0x24),(True,1,1,0x30),(True,0,2,0x31)):
 u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x51400000,0x400000);u.mem_write(base,rom);u.mem_map(0x80000000,0x120000)
 stop,req,reply,env,owner=0x80100000,0x80100100,0x80100200,0x80100300,0x800ca76c
 u.mem_write(req,bytes.fromhex('4260fa00'));u.mem_write(reply,b'\xa5'*4)
 u.mem_write(0x800ce053,bytes([2 if valid else 0]));u.mem_write(0x800ce1d4,b'\x01');u.mem_write(0x800ce5ba,bytes([flag]))
 registered=[];published=[];sent=[];freed=[];consumed=[]
 def hook(c,a,n,d):
  if a==stop:c.emu_stop();return
  r=[c.reg_read(i) for i in (UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3)]
  if a==0x514b9a44:assert r[0]==4;c.reg_write(UC_ARM_REG_R0,reply)
  elif a==0x514bddf8:
   ptr=struct.unpack('<I',c.mem_read(c.reg_read(UC_ARM_REG_SP),4))[0];assert r[1:]==[0x3012,env,0x14e8] and ptr==reply;registered.append(r)
  elif a==0x51615814:published.append(r[0])
  elif a==0x514bde34:
   assert r[1]==0x3013 and r[3]==env;c.mem_write(r[2],struct.pack('<I',reply));c.reg_write(UC_ARM_REG_R0,env);consumed.append(r)
  elif a==0x5165eb50:assert r==[owner,env,reply,4];sent.append(bytes(c.mem_read(reply,4)))
  elif a==0x514b9ab4:freed.append(r[0])
  elif a==0x51615ccc:pass
  else:return
  c.reg_write(UC_ARM_REG_PC,c.reg_read(UC_ARM_REG_LR))
 u.hook_add(UC_HOOK_CODE,hook)
 def call(entry,third):
  for r,v in ((UC_ARM_REG_CPSR,0x13),(UC_ARM_REG_SP,0x8011f000),(UC_ARM_REG_LR,stop|1),(UC_ARM_REG_R0,owner),(UC_ARM_REG_R1,0),(UC_ARM_REG_R2,env),(UC_ARM_REG_R3,third)):u.reg_write(r,v)
  u.emu_start(entry,0,count=50000);assert u.reg_read(UC_ARM_REG_PC)==stop and u.reg_read(UC_ARM_REG_SP)==0x8011f000
 call(0x516621ed,req);assert len(registered)==1 and published==[result] and freed==[req] and sent==[]
 call(0x51662241,published[0]);assert len(consumed)==1 and sent==[bytes((0x42,0x61,0xfa,status))] and freed==[req]
 assert bytes(u.mem_read(base,len(rom)))==rom
 reports.append(dict(cache_valid=valid,cipher_bit=flag,native_notification=result,reply=sent[0].hex(),fixture_delivery=True))
print(json.dumps(reports,indent=2))
