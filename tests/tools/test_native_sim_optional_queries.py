"""Native optional SIM reads must complete even when their caches are invalid.

Execute original handlers, cache getters and status mapper. Allocation, memory
utility and message transport leaves are fixture services, not a phone model.
Direct handler entry deliberately does not qualify SIM readiness/dispatch or
physical SIM initialization. Unsupported payload canaries remain undefined;
only the native response header/status and ownership are required.
"""
from pathlib import Path
import sys,json,hashlib,struct,collections
from unicorn import *
from unicorn.arm_const import *
root=Path(__file__).resolve().parents[2];blob=(root/'firmware/THC N-Gage ROM Dump/ngage-gsmstuff-0x5149D280.dll').read_bytes();assert hashlib.sha256(blob).hexdigest()=='e5870e918c90d9c7a6403eb0ee305d174e906aeae0a7fa8069e85a18aeec7aa1'
rom=blob[96:];base=0x5149d280
# Exact original native service/method bindings, independent of donor addresses.
rows=[]
for address in range(0x516e02a8,0x516e09b8,12):
 req,svc,resp,zero,method,unused,obj=struct.unpack_from('<BBBBHHI',rom,address-base)
 if (req,svc) not in ((0x21,0x2c),(0x13,0x11),(0x31,0x3b),(0x33,0x3e),(0x29,0x37)):continue
 matches=[hex(struct.unpack_from('<I',rom,off+4)[0]) for off in range(0,len(rom)-8,4)
          if struct.unpack_from('<I',rom,off)[0]==method and
          0x51400000<=struct.unpack_from('<I',rom,off+4)[0]<0x51717000]
 assert len(matches)==1
 rows.append(dict(request=f'{req:02x}',service=f'{svc:02x}',response=f'{resp:02x}',
                  method=f'{method:04x}',object=hex(obj),method_targets=matches))
assert len(rows)==5
reports=[]
for req,svc in ((0x21,0x2c),(0x13,0x11),(0x31,0x3b),(0x33,0x3e),(0x29,0x37)):
 row=next(r for r in rows if int(r['request'],16)==req and int(r['service'],16)==svc);entry=int(row['method_targets'][0],16);owner=int(row['object'],16)
 u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x51400000,0x400000);u.mem_write(base,rom);u.mem_map(0x80000000,0x120000)
 stop,request,reply,envelope=0x80100000,0x80100100,0x80100200,0x80100300
 u.mem_write(request,bytes((0x42,req,svc,0,0,0,0,0)));u.mem_write(reply,b'\xa5'*256)
 sent=[];freed=[];allocs=[];pcs=collections.deque(maxlen=12)
 def hook(cpu,a,n,d):
  pcs.append(hex(a))
  if a==stop:cpu.emu_stop();return
  r=[cpu.reg_read(i) for i in (UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3)]
  if a==0x514b9a44:
   assert 1<=r[0]<=256;allocs.append(r[0]);cpu.reg_write(UC_ARM_REG_R0,reply)
  elif a==0x5165eb50:
   assert r[:3]==[owner,envelope,reply];sent.append(bytes(cpu.mem_read(r[2],r[3])))
  elif a==0x514b9ab4:freed.append(r[0])
  elif a==0x516c74f4:cpu.mem_write(r[0],bytes(cpu.mem_read(r[1],r[2])))
  elif a==0x516c752c:cpu.mem_write(r[0],bytes([r[1]&255])*r[2])
  elif a in (0x51615ccc,0x516c757c,0x516c7584):pass
  else:return
  cpu.reg_write(UC_ARM_REG_PC,cpu.reg_read(UC_ARM_REG_LR))
 u.hook_add(UC_HOOK_CODE,hook)
 for r,v in ((UC_ARM_REG_CPSR,0x13),(UC_ARM_REG_SP,0x8011f000),(UC_ARM_REG_LR,stop|1),(UC_ARM_REG_R0,owner),(UC_ARM_REG_R1,0),(UC_ARM_REG_R2,envelope),(UC_ARM_REG_R3,request)):u.reg_write(r,v)
 try:u.emu_start(entry,0,count=50000)
 except UcError as ex:print('ERROR',hex(req),str(ex),list(pcs));raise
 assert u.reg_read(UC_ARM_REG_PC)==stop,(hex(req),list(pcs))
 assert u.reg_read(UC_ARM_REG_SP)==0x8011f000
 assert freed==[request] and len(sent)==1,(hex(req),freed,sent)
 assert sent[0][:3]==bytes((0x42,int(row['response'],16),svc))
 assert sent[0][3]==0x24,(hex(req),sent[0].hex())
 assert bytes(u.mem_read(base,len(rom)))==rom
 reports.append(dict(request=row['request'],service=row['service'],entry=hex(entry),alloc=allocs,reply=sent[0].hex(),native_missing_cache_completion=True))
print(json.dumps(reports,indent=2))
