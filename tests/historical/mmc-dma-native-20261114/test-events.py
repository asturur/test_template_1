exec(open('scratch/mmc-dma-native-20261114/test.py').read().replace("print('PASS 192 ARM direct-port observer ABI/flags/stack/output and displaced-instruction cases; actual byte-output instructions, original MMC behavior unmodified')",''))
for name,resume in [('flags',0x503f5570),('status',0x503f5304)]:
 for case in range(64):
  u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x50000000,0x1400000);u.mem_write(0x511bd000,b);u.mem_map(0x80000000,0x100000);u.mem_map(0x59000000,4096)
  flags=(rnd.randrange(16)<<28)|0x13;u.reg_write(UC_ARM_REG_CPSR,flags);sp=0x800ff000;u.reg_write(UC_ARM_REG_SP,sp)
  original=[rnd.getrandbits(32) for r in regs];original[4 if name=='flags' else 7]=0x80010000
  obj=bytes(rnd.getrandbits(8) for _ in range(0x900));u.mem_write(0x80010000,obj);word=lambda off:struct.unpack_from('<I',obj,off)[0]
  if name=='status' and case%2==0:original[3]=word(0x8c8)
  for r,v in zip(regs,original):u.reg_write(r,v)
  output=[]
  def hook(c,a,n,d):
   if a==resume:c.emu_stop()
  def write(c,access,a,size,value,data):
   if a==0x59000000:assert size==1;output.append(value)
  u.hook_add(UC_HOOK_CODE,hook);u.hook_add(UC_HOOK_MEM_WRITE,write);u.emu_start(int(syms['mmc_'+name],16),0,count=3000)
  expected=([original[5],word(0x8a8),word(0x8c8),word(0x8b4),word(0x8cc)] if name=='flags' else [original[3],word(0x8ac),word(0x8a8),word(0x8b4),original[6]])
  expect_bytes=bytes([0xc0])+('M '+('Q' if name=='flags' else 'S')+' '+(' '.join(f'{v:08x}' for v in expected))+(' ' if name=='flags' else '')+'\n').encode()
  if name=='status' and original[3]==word(0x8c8):expect_bytes=b''
  assert bytes(output)==expect_bytes,(name,bytes(output),expect_bytes)
  if name=='flags':original[0]=original[5]
  else:original[4]=original[3]
  assert [u.reg_read(r) for r in regs]==original
  assert u.reg_read(UC_ARM_REG_PC)==resume and u.reg_read(UC_ARM_REG_SP)==sp and u.reg_read(UC_ARM_REG_CPSR)==flags
  assert bytes(u.mem_read(0x80010000,len(obj)))==obj
print('PASS 320 cases across all five direct-port MMC observer hooks: exact output, silent paths, GPRs/CPSR/SP and observed memory')
