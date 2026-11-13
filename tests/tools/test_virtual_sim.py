"""Execute original NEM4 response lookup/send/indication builders with the shim."""
from pathlib import Path
import importlib.util
import json
import struct
import sys
from unicorn import Uc,UC_ARCH_ARM,UC_MODE_ARM,UC_HOOK_CODE
from unicorn.arm_const import *
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
import build_virtual_sim as builder
PRODUCTION='--production' in sys.argv
OUT=ROOT/'build/firmware-overlays'/('virtual-sim-production' if PRODUCTION else 'virtual-sim')
plan=json.loads((OUT/'sim.json').read_text());rule=builder.rules()
nos=(ROOT/'firmware/THC N-Gage ROM Dump/ngage-gsmstuff-0x5149D280.dll').read_bytes()[96:]
STOP=0x51400000;SERVER=0x800ca784;OBJECT=0x800ca7fc
REQUEST=0x80101000;REPLY=0x80102000;META=0x80103000

def fixture(state):
 u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x51400000,0x400000);u.mem_write(0x5149d280,nos)
 for off,old,new in plan['records']:
  data=struct.pack('<I',new)
  if 0xa000<=off<0x2b3000:
   data=b''.join(struct.pack('<H',builder.decode16(struct.unpack_from('<H',data,i)[0],off+i,rule)) for i in (0,2))
  u.mem_write(0x51400000+off,data)
 u.mem_map(0x59000000,4096);u.mem_map(0x80000000,0x100000);u.mem_map(0x80100000,0x10000)
 u.mem_write(SERVER+8,bytes([state]));u.mem_write(SERVER+6,b'\x09')
 u.mem_write(OBJECT+4,struct.pack('<I',SERVER));u.reg_write(UC_ARM_REG_CPSR,0x13)
 u.reg_write(UC_ARM_REG_SP,0x8010f000);u.reg_write(UC_ARM_REG_LR,STOP|1)
 for r,v in zip((UC_ARM_REG_R4,UC_ARM_REG_R5,UC_ARM_REG_R6,UC_ARM_REG_R7,UC_ARM_REG_R8,UC_ARM_REG_R9,UC_ARM_REG_R10,UC_ARM_REG_R11),range(4,12)):u.reg_write(r,v)
 return u

def finish(u):
 assert u.reg_read(UC_ARM_REG_PC)==STOP
 assert u.reg_read(UC_ARM_REG_SP)==0x8010f000
 for r,v in zip((UC_ARM_REG_R4,UC_ARM_REG_R5,UC_ARM_REG_R6,UC_ARM_REG_R7,UC_ARM_REG_R8,UC_ARM_REG_R9,UC_ARM_REG_R10,UC_ARM_REG_R11),range(4,12)):assert u.reg_read(r)==v

def response(req,expected,state=5):
 u=fixture(state);u.mem_write(REQUEST,bytes((0x42,))+req+bytes(8));events=[];sent=[];lengths={};allocs=[];indications=[]
 def hook(u,a,n,d):
  if a==STOP:u.emu_stop();return
  if a==0x514b9a44:
   size=u.reg_read(UC_ARM_REG_R0);assert size in (8,16)
   address=REPLY+len(allocs)*256;allocs.append(address);events.append('allocate')
   u.mem_write(address,b'\xaa'*16);u.reg_write(UC_ARM_REG_R0,address)
  elif a==0x514b9ab4:
   assert u.reg_read(UC_ARM_REG_R0)==REQUEST;events.append('free request')
  elif a==0x51615d58:events.append('native trace')
  elif a==0x514b9b3c:
   address=u.reg_read(UC_ARM_REG_R0);assert address in allocs
   lengths[address]=u.reg_read(UC_ARM_REG_R1);events.append('native length')
  elif a==0x514ba308:
   assert u.reg_read(UC_ARM_REG_R0)==SERVER and u.reg_read(UC_ARM_REG_R1)==9
   address=u.reg_read(UC_ARM_REG_R2);assert lengths[address]==8
   indications.append(bytes(u.mem_read(address,8)));events.append('ready indication')
  elif a==0x514bde34:
   address=u.reg_read(UC_ARM_REG_R3)
   assert [u.reg_read(r) for r in (UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2)]==[META,0xc008,SERVER]
   sent.append(bytes(u.mem_read(address,lengths[address])));events.append('native send')
  elif a==0x514bde9c:
   assert u.reg_read(UC_ARM_REG_R0)==META and u.reg_read(UC_ARM_REG_R1)==0xc00b;events.append('native envelope release')
  else:return
  if a!=0x514b9a44:u.reg_write(UC_ARM_REG_R0,0)
  u.reg_write(UC_ARM_REG_PC,u.reg_read(UC_ARM_REG_LR))
 u.hook_add(UC_HOOK_CODE,hook)
 for r,v in zip((UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3),(OBJECT,0,META,REQUEST)):u.reg_write(r,v)
 u.emu_start(plan['symbols']['virtual_sim_request'],0,count=20000);finish(u)
 assert sent==[bytes((0x42,))+expected],(req,sent,expected)
 assert events.count('free request')==1 and events.count('native envelope release')==1
 assert events.index('free request')<events.index('native send')
 assert indications==([bytes.fromhex('00ef0d0b08010000')] if state in (5,6) else [])
 if state in (5,6):assert events.index('ready indication')<events.index('native send')
 assert bytes(u.mem_read(SERVER+8,1))==bytes([8 if state in (5,6,8) else state])

cases=[('60fa','61fa31'),('212c','222c24'),('333e','343e24'),('1311','141124'),
 ('313b','323b24'),('3bfa','3cfa2a'),('2d3a','2e3a010000'),
 ('2b3a','2c3a0101000000'),('192f','1a2f0100f11000'),
 ('1d2d','1e2d01080910101032547698000000'),('fe99','fe99fa')]
for req,expected in cases:
 response(bytes.fromhex(req),bytes.fromhex(expected));response(bytes.fromhex(req),bytes.fromhex(expected),6);response(bytes.fromhex(req),bytes.fromhex(expected),8)
# Non-selected physical states still execute the original native fallback.
response(bytes.fromhex('60fa'),bytes.fromhex('61fafc0701aaaa'),7)

def indication(entry,state,other_server=False):
 u=fixture(state);sent=[]
 def hook(u,a,n,d):
  if a==STOP:u.emu_stop();return
  if a==0x514b9a44:u.reg_write(UC_ARM_REG_R0,REPLY)
  elif a==0x514b9b3c:
   assert u.reg_read(UC_ARM_REG_R0)==REPLY and u.reg_read(UC_ARM_REG_R1)==8
  elif a==0x514ba308:
   assert u.reg_read(UC_ARM_REG_R0)==SERVER
   assert u.reg_read(UC_ARM_REG_R1)==9
   sent.append(bytes(u.mem_read(u.reg_read(UC_ARM_REG_R2),8)));u.reg_write(UC_ARM_REG_R0,0)
  else:return
  u.reg_write(UC_ARM_REG_PC,u.reg_read(UC_ARM_REG_LR))
 u.hook_add(UC_HOOK_CODE,hook)
 for r,v in zip((UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3),(OBJECT,13,11,0x74)):u.reg_write(r,v)
 u.emu_start(entry|1,0,count=20000);finish(u);assert len(sent)==1
 assert sent[0][0:2]==b'\0\xef'
 if state in (5,6):assert sent[0]==bytes.fromhex('00ef0d0b08010000'),sent
 else:assert sent[0][4]==state
 assert bytes(u.mem_read(SERVER+8,1))==bytes([8 if state in (5,6) else state])
for state in (1,5,6):indication(0x5165ed78,state)
for state in (5,6):indication(0x51661924,state)
print('PASS virtual SIM: original response-id table/send path,11 query cases/two absent states, original other-state fallback, both original indication builders, request/envelope ownership and coherent ready transition; no duplicate indication in state8')

# Execute the native35/02 receiver and its re-encoded Thumb call to the new
# observer. Keep the original result builder as a single fixture leaf.
u=fixture(8);native_packet=bytes.fromhex('42030c0001040702');u.mem_write(REPLY,native_packet)
u.mem_write(REQUEST,bytes.fromhex('42020200'));u.mem_write(0x8010f000,struct.pack('<I',0x3502));observed=[];released=[]
def selftest_hook(u,a,n,d):
 if a==STOP:u.emu_stop();return
 if a==0x5164a4a8:u.reg_write(UC_ARM_REG_R0,REPLY)
 elif a==0x514b9b48:
  assert u.reg_read(UC_ARM_REG_R0)==REPLY;u.reg_write(UC_ARM_REG_R0,len(native_packet))
 elif a==0x514bddf8:
  assert [u.reg_read(r) for r in (UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3)]==[META,0xc011,SERVER,0x35]
  assert struct.unpack('<I',u.mem_read(u.reg_read(UC_ARM_REG_SP),4))[0]==REPLY
  observed.append(bytes(u.mem_read(REPLY,len(native_packet))));u.reg_write(UC_ARM_REG_R0,0)
 elif a==0x514b9ab4:
  released.append(u.reg_read(UC_ARM_REG_R0));u.reg_write(UC_ARM_REG_R0,0)
 else:return
 u.reg_write(UC_ARM_REG_PC,u.reg_read(UC_ARM_REG_LR))
u.hook_add(UC_HOOK_CODE,selftest_hook)
for r,v in zip((UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3),(SERVER,0,META,REQUEST)):u.reg_write(r,v)
u.emu_start(0x51591811,0,count=20000);finish(u)
assert observed==[native_packet] and released==[REQUEST]
print('PASS native selftest observer: original35/02 receiver, unaligned encrypted Thumb call, all five dispatch arguments, unchanged packet, request release and return')

# The asynchronous completion has a separate send site. Execute that native
# callback and check the CPU-visible result array remains observation-only.
from unicorn import UC_HOOK_MEM_WRITE
u=fixture(8);u.mem_write(REPLY,bytes.fromhex('00010c00'));u.mem_write(REQUEST,b'\0'*8)
u.mem_write(0x80009d18,struct.pack('<I',META));u.mem_write(0x80009d1c,struct.pack('<I',REQUEST))
u.mem_write(0x80024388,bytes(range(24)));async_sent=[];async_freed=[];wire=[]
def async_hook(u,a,n,d):
 if a==STOP:u.emu_stop();return
 if a==0x5164a31c:u.reg_write(UC_ARM_REG_R0,REPLY)
 elif a==0x514b9b48:
  assert u.reg_read(UC_ARM_REG_R0)==REPLY;u.reg_write(UC_ARM_REG_R0,4)
 elif a==0x514bddf8:
  assert [u.reg_read(r) for r in (UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3)]==[META,0xc011,SERVER,0x35]
  assert struct.unpack('<I',u.mem_read(u.reg_read(UC_ARM_REG_SP),4))[0]==REPLY
  async_sent.append(bytes(u.mem_read(REPLY,4)));u.reg_write(UC_ARM_REG_R0,0)
 elif a==0x514b9ab4:
  async_freed.append(u.reg_read(UC_ARM_REG_R0));u.reg_write(UC_ARM_REG_R0,0)
 elif a==0x514bde9c:
  assert u.reg_read(UC_ARM_REG_R0)==META and u.reg_read(UC_ARM_REG_R1)==0xc00b;u.reg_write(UC_ARM_REG_R0,0)
 else:return
 u.reg_write(UC_ARM_REG_PC,u.reg_read(UC_ARM_REG_LR))
def on_wire(u,access,address,size,value,data):
 if address==0x59000000:assert size==1;wire.append(value)
u.hook_add(UC_HOOK_CODE,async_hook);u.hook_add(UC_HOOK_MEM_WRITE,on_wire)
u.reg_write(UC_ARM_REG_R0,SERVER);u.emu_start(0x515919ed,0,count=20000);finish(u)
assert async_sent==[bytes.fromhex('00010c00')] and async_freed==[REQUEST]
assert bytes(u.mem_read(0x80024388,24))==bytes(range(24))
assert bytes(u.mem_read(0x80009d18,8))==bytes(8)
lines=bytes(wire).decode().splitlines()
assert [line for line in lines if line.startswith('V S ')]==([] if PRODUCTION else [f'V S {int.from_bytes(bytes(range(i,i+4)),"little"):08x}' for i in range(0,24,4)])
if PRODUCTION:
 assert not wire,'production must not write the diagnostic port'
 assert not any(off in (0x1919b4,0x1919b8,0x191a60) for off,old,new in plan['records']),'production must retain original self-test send sites'
print('PASS native async selftest callback: five-argument send, result array readback, unchanged failure packet/results, pending-envelope and request cleanup')

def startup_tests(group,original):
 v=fixture(8)
 if original:
  v.mem_write(0x516f79a7,b'\x02');v.mem_write(0x516f79c7,b'\x02')
 v.mem_write(REQUEST,bytes((0,2,group,0)));v.mem_write(0x80105030,b'\0');ids=[]
 def stop(v,a,n,d):
  if a==STOP:v.emu_stop()
 v.hook_add(UC_HOOK_CODE,stop)
 for repeat in range(30):
  for r,x in zip((UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3),(0x80105000,0x80105020,REQUEST,0x80105030)):v.reg_write(r,x)
  v.reg_write(UC_ARM_REG_LR,STOP|1);v.emu_start(0x5164ad15,0,count=20000)
  assert v.reg_read(UC_ARM_REG_PC)==STOP
  if v.reg_read(UC_ARM_REG_R0)==0:break
  ids.append(v.mem_read(0x8010500a,1)[0])
 else:raise AssertionError('unbounded enumeration')
 for descriptor in (0x516f799c,0x516f79bc):
  original_bytes=nos[descriptor-0x5149d280:descriptor-0x5149d280+16]
  actual=bytes(v.mem_read(descriptor,16))
  assert actual[:11]==original_bytes[:11] and actual[12:]==original_bytes[12:]
 return ids
assert startup_tests(1,True)==startup_tests(1,False)==[0x13,0x2e,3,0x11,0x0c,0x0d,8,0x14]
assert startup_tests(2,True)==[7,0x2b,0x15,2,0x1e,0x36]
assert startup_tests(2,False)==[7,0x2b,0x15,2]
print('PASS native startup-test applicability: group1 identical, group2 excludes only absent RF/ADSP, explicit test functions/IDs/severity retained')
