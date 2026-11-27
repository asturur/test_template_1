"""Check native SIM fallback tracing without changing firmware or service state."""
from pathlib import Path
import json
import struct
from unicorn import Uc,UC_ARCH_ARM,UC_MODE_ARM,UC_HOOK_CODE,UC_HOOK_MEM_WRITE
from unicorn.arm_const import *
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/firmware-overlays/sim-trace'
report=json.loads((OUT/'trace.json').read_text())
raw=(ROOT/'scratch/menu-bringup-20261112/raw-original.bin').read_bytes()
for off,old,target in report['hooks']:
 assert struct.unpack_from('<I',raw,off)[0]==old
for index,kind,target in ((0,'N',0x5165ed25),(1,'P',0x5165ecd1)):
 for state in (1,5,8):
  u=Uc(UC_ARCH_ARM,UC_MODE_ARM)
  u.mem_map(0x511b7000,4096);u.mem_write(0x511b7000,(OUT/'trace.bin').read_bytes())
  u.mem_map(0x5165e000,4096);u.mem_map(0x400000,65536)
  u.mem_map(0x800ca000,4096);u.mem_write(0x800ca78c,bytes([state]))
  u.mem_map(0x59000000,4096)
  regs=[UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3,
        UC_ARM_REG_R4,UC_ARM_REG_R5,UC_ARM_REG_R6,UC_ARM_REG_R7,
        UC_ARM_REG_R8,UC_ARM_REG_R9,UC_ARM_REG_R10,UC_ARM_REG_R11,
        UC_ARM_REG_SP,UC_ARM_REG_LR]
  values=[0x800ca7fc,22,0x402000,0x400ffd,4,5,6,7,8,9,10,11,0x40f000,0x50123457]
  for r,v in zip(regs,values):u.reg_write(r,v)
  u.reg_write(UC_ARM_REG_CPSR,0xa0000013)
  u.mem_write(0x400ffd,bytes((1,0x60,0xfa)));text=[]
  def on_write(u,access,a,n,v,d):
   if a==0x59000000:
    assert n==1;text.append(v)
  def on_code(u,a,n,d):
   if a==target&~1:u.emu_stop()
  u.hook_add(UC_HOOK_MEM_WRITE,on_write);u.hook_add(UC_HOOK_CODE,on_code)
  u.emu_start(0x511b7000+4*index,0,count=1000)
  assert u.reg_read(UC_ARM_REG_PC)==target&~1
  assert u.reg_read(UC_ARM_REG_CPSR)&0xf000003f==0xa0000033
  for r,v in zip(regs,values):assert u.reg_read(r)==v,(r,hex(u.reg_read(r)),hex(v))
  assert bytes(text)==f'Y SIM {kind} {state:02x}fa6001\n'.encode()
  assert bytes(u.mem_read(0x800ca78c,1))==bytes([state])
print('PASS native SIM trace: raw method identities, both fallbacks/states, bounded byte reads, register/flags/SP preservation, original Thumb tailcall')
