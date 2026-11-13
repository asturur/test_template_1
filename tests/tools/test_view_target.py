"""Exercise actual NEM4 FullName/descriptor/memcpy with only exec/print leaves stubbed."""
from pathlib import Path
import subprocess,struct
from unicorn import Uc,UC_ARCH_ARM,UC_MODE_ARM,UC_HOOK_CODE
from unicorn.arm_const import *
root=Path(__file__).resolve().parents[2];out=root/'build/firmware-overlays/exit-trace'
symbols={p[2]:int(p[0],16) for line in subprocess.check_output(['arm-none-eabi-nm',str(out/'trace.elf')],text=True).splitlines() if len(p:=line.split())==3}
def run(context_status=0,context_length=72):
 u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x50000000,0x1400000);u.mem_write(0x50000000,(root/'firmware/SYM.ROM').read_bytes());u.mem_write(0x511b6000,(out/'trace.bin').read_bytes());u.mem_map(0x400000,0x400000)
 u.reg_write(UC_ARM_REG_CPSR,0x80000010)
 values={UC_ARM_REG_R0:0x41cf78,UC_ARM_REG_R1:0x701e78,UC_ARM_REG_R2:11,UC_ARM_REG_R3:0x12345678,UC_ARM_REG_R6:11,UC_ARM_REG_R12:0xabcd,UC_ARM_REG_LR:0x5064dd55,UC_ARM_REG_SP:0x701e78}
 for reg,value in values.items():u.reg_write(reg,value)
 u.mem_write(0x41cf78,struct.pack('<I',0x123));prints=[];execs=[];operations=[];name='Phone[100058b3]::Main'
 def hook(u,a,size,data):
  if a==0x503b8014:u.emu_stop()
  elif a==0x503ac68c:
   desc=u.reg_read(UC_ARM_REG_R0);handle=u.reg_read(UC_ARM_REG_R1);assert handle==0x123;execs.append(handle)
   header,maxlen=struct.unpack('<II',u.mem_read(desc,8));assert maxlen==256 and header&0xf0000000==0x30000000
   u.mem_write(desc,struct.pack('<I',0x30000000|len(name)));u.mem_write(desc+8,name.encode('utf-16le'));u.reg_write(UC_ARM_REG_PC,u.reg_read(UC_ARM_REG_LR))
  elif a in (0x503ac5f8,0x503ac5f4,0x503ac614):
   assert u.reg_read(UC_ARM_REG_R0)==0x123
   operations.append({0x503ac5f8:'suspend',0x503ac5f4:'resume',0x503ac614:'requests'}[a])
   if a==0x503ac614:u.reg_write(UC_ARM_REG_R0,0xffffffff)
   u.reg_write(UC_ARM_REG_PC,u.reg_read(UC_ARM_REG_LR))
  elif a==0x503ac7c0:
   assert u.reg_read(UC_ARM_REG_R1)==0x123
   desc=u.reg_read(UC_ARM_REG_R0);h,m=struct.unpack('<II',u.mem_read(desc,8));assert h==0x30000000 and m==256
   operations.append('context');u.mem_write(desc,struct.pack('<I',0x30000000|context_length))
   u.mem_write(desc+8,struct.pack('<18I',*range(18)));u.reg_write(UC_ARM_REG_R0,context_status&0xffffffff);u.reg_write(UC_ARM_REG_PC,u.reg_read(UC_ARM_REG_LR))
  elif a==0x503b409c:
   desc=u.reg_read(UC_ARM_REG_R0);header,ptr=struct.unpack('<II',u.mem_read(desc,8));text=bytes(u.mem_read(ptr,(header&0xfffffff)*2)).decode('utf-16le');prints.append(text)
   if text=='X VIEW_TARGET %S':
    arg=u.reg_read(UC_ARM_REG_R1);h=struct.unpack('<I',u.mem_read(arg,4))[0];assert h&0xf0000000==0x30000000;assert bytes(u.mem_read(arg+8,(h&0xfffffff)*2)).decode('utf-16le')==name
   lr=u.reg_read(UC_ARM_REG_LR)
   for reg in (UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3,UC_ARM_REG_R12):u.reg_write(reg,0)
   u.reg_write(UC_ARM_REG_CPSR,0x60000010);u.reg_write(UC_ARM_REG_PC,lr)
 u.hook_add(UC_HOOK_CODE,hook);u.emu_start(symbols['trace_thread_panic'],0,count=20000)
 assert u.reg_read(UC_ARM_REG_PC)==0x503b8014 and execs==[0x123]
 assert prints[0]=='X VIEW_TARGET %S' and prints[-1].startswith('X THREAD_PANIC ')
 assert operations==['suspend','requests','context','resume']
 assert sum(p.startswith('X CTX') for p in prints)==(6 if context_length>=72 else 0)
 for reg,value in values.items():
  assert u.reg_read(reg)==(value-4 if reg==UC_ARM_REG_SP else value),(reg,hex(u.reg_read(reg)),hex(value))
 assert int.from_bytes(u.mem_read(values[UC_ARM_REG_SP]-4,4),'little')==values[UC_ARM_REG_LR]
 assert u.reg_read(UC_ARM_REG_CPSR)&0xf0000000==0x80000000
run();run(0x701c40,72);run(-5,0);run(0,8)
print('PASS ViewSrv target/context: actual EUser wrappers, balanced suspend/resume, success/error/short guards, register/flags/SP preservation')
