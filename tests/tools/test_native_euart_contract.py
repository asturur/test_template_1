"""Unchanged EUART1 TX and RX interrupt driver, including actual HAL MMIO.

RTOS polling and logical-channel callbacks are fixture services. This proves
native byte/register ownership, not serial timing or external DSP responses.
"""
from pathlib import Path
import hashlib,struct
from unicorn import *
from unicorn.arm_const import *
ROOT=Path(__file__).resolve().parents[2]
rom=(ROOT/'build/firmware/nem4-factory/core.bin').read_bytes()
assert hashlib.sha256(rom).hexdigest()=='be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524'

def verify(transmit):
 u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x50000000,0x1400000);u.mem_write(0x50000000,rom)
 u.mem_map(0x80000000,0x10000);u.mem_map(0x58000000,0x160000)
 stop=0x80000000;callback=stop+4;obj=stop+0x100;channel=stop+0x300;vt=stop+0x400;irq=stop+0x500
 packet=[0x7e,0x82,0x2b];sent=[];received=[];writes=[];index=0
 def word(a,v):u.mem_write(a,struct.pack('<I',v))
 word(obj+4,channel);word(channel,vt);word(vt+0x30,callback);word(vt+0x2c,callback)
 word(irq+0x14,obj)
 def code(u,a,n,data):
  nonlocal index
  if a==stop:u.emu_stop();return
  if a==0x510e8f50:u.reg_write(UC_ARM_REG_R0,1) # Native RTOS bounded poll leaf.
  elif a==callback:
   assert u.reg_read(UC_ARM_REG_R0)==channel
   if transmit:
    u.reg_write(UC_ARM_REG_R0,packet[index] if index<len(packet) else 0xffffffff);index+=1
   else:received.append(u.reg_read(UC_ARM_REG_R1))
  else:return
  u.reg_write(UC_ARM_REG_PC,u.reg_read(UC_ARM_REG_LR))
 def mem(u,kind,a,size,value,data):
  nonlocal index
  if kind==UC_MEM_WRITE:
   writes.append((a,size,value))
   if a==0x58150554:sent.append(value>>8)
  elif a==0x58150514:u.mem_write(a,struct.pack('<H',4))
  elif a==0x581500ba:u.mem_write(a,struct.pack('<H',8 if not transmit else 0))
  elif a==0x58150562:
   u.mem_write(a,struct.pack('<H',(len(packet)<<4)|index if not transmit else 0))
  elif a==0x58150556:
   assert index<len(packet);u.mem_write(a,struct.pack('<H',packet[index]<<8));index+=1
 u.hook_add(UC_HOOK_CODE,code)
 u.hook_add(UC_HOOK_MEM_READ|UC_HOOK_MEM_WRITE,mem,begin=0x58000000,end=0x5815ffff)
 for reg,val in ((UC_ARM_REG_CPSR,0x13),(UC_ARM_REG_SP,0x8000f000),(UC_ARM_REG_LR,stop),
                 (UC_ARM_REG_R0,obj if transmit else irq)):
  u.reg_write(reg,val)
 u.emu_start(0x510e8be8 if transmit else 0x510e8d58,0,count=50000)
 assert u.reg_read(UC_ARM_REG_PC)==stop and u.reg_read(UC_ARM_REG_SP)==0x8000f000
 assert bytes(u.mem_read(0x50000000,len(rom)))==rom
 if transmit:
  assert sent==packet,(sent,writes)
  assert writes==[(0x5815055a,2,2)]+[(0x58150554,2,b<<8) for b in packet],writes
 else:
  assert received==packet,(received,writes)
  assert writes==[(0x581500ba,2,8)],writes
verify(True);verify(False)
print('PASS original EUART1 TX and RX IRQ: count-minus-one, high-byte data, FIFO indices, RX status ACK, callbacks and ROM unchanged')
