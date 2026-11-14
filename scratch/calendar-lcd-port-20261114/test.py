import struct,hashlib
from pathlib import Path
from unicorn import *
from unicorn.arm_const import *
p=Path('scratch/calendar-lcd-port-20261114');rom=Path('build/firmware/nem4-factory/core.bin').read_bytes();blob=(p/'trace.bin').read_bytes();syms={a[2]:int(a[0],16) for l in (p/'symbols.txt').read_text().splitlines() if len(a:=l.split())==3};cases=0
assert hashlib.sha256(rom).hexdigest()=='be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524'
def run(name,entry,args,flags,thumb,mode,traced,proc_mode=0x10,dma=None):
 u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x50000000,0x1400000);u.mem_write(0x50000000,rom);u.mem_write(0x511b8000,blob);u.mem_map(0x59000000,4096);u.mem_map(0x80000000,0x100000)
 u.mem_write(0x80002070,struct.pack('<I',mode));u.mem_write(0x80003000,struct.pack('<III',args[1] if name=='line' else 55,0,0x80004000));u.mem_write(0x80004000,b''.join(struct.pack('<I',(i*0x1079b+0xabc)&0xffffff) for i in range(176)))
 vals=[0x100+i for i in range(13)];vals[:2]=[0x80002000,0x80003000] if name=='line' else args;regs=[UC_ARM_REG_R0+i for i in range(13)];lr=(0x5040184c if dma else 0x80000000)|thumb;ports=[];logs=[];text=[]
 if dma:
  vals[4],vals[5],vals[7]=dma[0],0x80002000,dma[1];u.mem_write(0x80002038,struct.pack("<I",0x80004000));u.mem_write(0x80004000,b"".join(struct.pack("<H",(i*17+3)&0xfff) for i in range(176*208)))
 def ret(c):c.reg_write(UC_ARM_REG_PC,c.reg_read(UC_ARM_REG_LR))
 def code(c,a,n,d):
  if a==(lr&~1):c.emu_stop();return
  if a in (0x50404c18,0x50404558,0x50404510,0x504004ec):ports.append([a,c.reg_read(UC_ARM_REG_R0),c.reg_read(UC_ARM_REG_R1) if a==0x50404c18 else None])
  else:return
  for r in regs[:4]+[UC_ARM_REG_R12]:c.reg_write(r,0x55555555)
  c.reg_write(UC_ARM_REG_R0,0);c.reg_write(UC_ARM_REG_CPSR,(c.reg_read(UC_ARM_REG_CPSR)&0x0fffffff)|0xa0000000);ret(c)
 def write(c,access,addr,size,value,data):
  if addr==0x59000000:assert size==1;text.append(value&255)
 u.hook_add(UC_HOOK_MEM_WRITE,write);u.hook_add(UC_HOOK_CODE,code);u.reg_write(UC_ARM_REG_CPSR,proc_mode|flags);u.reg_write(UC_ARM_REG_SPSR,0x60000010);u.reg_write(UC_ARM_REG_SP,0x800ff000);u.reg_write(UC_ARM_REG_LR,lr)
 for r,v in zip(regs,vals):u.reg_write(r,v)
 if traced:u.mem_write(entry,struct.pack('<I',0xea000000|(((syms[name+'_trace']-entry-8)//4)&0xffffff)))
 
 try:u.emu_start(entry,0,count=20000)
 except UcError:
  print('failed',name,args,mode,flags,thumb,traced,hex(u.reg_read(UC_ARM_REG_PC)));raise
 assert u.reg_read(UC_ARM_REG_PC)==(lr&~1)
 assert bool(text)==traced
 if text:
  msg=bytes(text);assert msg[0]==192;decoded=msg[1:].decode('ascii')
  sample=((25*0x1079b+0xabc)&0xffffff) if name=='line' else 0
  if dma and dma[1]:
   y=60 if dma[0]<=60<sum(dma) else dma[0];sample=((y*176+25)*17+3)&0xfff
  expected=(f'L LINE row={args[1]:08x} mode={mode:08x} sample25={sample:08x}' if name=='line' else f'L WINDOW start={args[0]:08x} end={args[1]:08x} caller={lr:08x}' if name=='window' else f'L {name.upper()} bytes={args[0]:08x} caller={lr:08x} sample25={sample:08x}')
  assert decoded==expected,(decoded,expected)
 return dict(regs=[u.reg_read(r) for r in regs]+[u.reg_read(UC_ARM_REG_SP),u.reg_read(UC_ARM_REG_LR),u.reg_read(UC_ARM_REG_CPSR),u.reg_read(UC_ARM_REG_SPSR)],ports=ports,memory=bytes(u.mem_read(0x80002000,0x3000)))
for name,entry,args in [('window',0x50400544,(0,208)),('window',0x50400544,(54,55)),('header12',0x50400640,(264,0)),('header12',0x50400640,(54912,0)),('header16',0x50400668,(528,0)),('line',0x50400efc,(0,1)),('line',0x50400efc,(0,55)),('line',0x50400efc,(0,208))]:
 for mode in ([10,7] if name=='line' else [10]):
  for flags in [0,0x60000000,0x90000000]:
   for thumb in [0,1]:
    for proc_mode in [0x10,0x13,0x12,0x1b]:
     assert run(name,entry,args,flags,thumb,mode,False,proc_mode)==run(name,entry,args,flags,thumb,mode,True,proc_mode),(name,args,mode,flags,thumb,proc_mode);cases+=1
for band in [(0,208),(45,141),(70,9),(0,0)]:
 for proc_mode in [0x10,0x13,0x12,0x1b]:
  assert run('header12',0x50400640,(264*band[1],0),0x90000000,0,10,False,proc_mode,band)==run('header12',0x50400640,(264*band[1],0),0x90000000,0,10,True,proc_mode,band);cases+=1
print('PASS',cases,'direct-port native LCD differential cases: registers/CPSR/SPSR/SP/LR, object/row/pixel memory and full port sequence match in USR/SVC/IRQ/UND, ARM/Thumb returns; DMA source sample within requested band; no debug service/SWI')
