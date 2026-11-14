exec(open('scratch/mmc-dma-native-20261114/test-events.py').read())
for case in range(64):
 u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x50000000,0x1400000);u.mem_write(0x511bd000,b);u.mem_map(0x80000000,0x100000);u.mem_map(0x59000000,4096);u.mem_map(0x58120000,4096)
 flags=(rnd.randrange(16)<<28)|0x13;u.reg_write(UC_ARM_REG_CPSR,flags);sp=0x800ff000;u.reg_write(UC_ARM_REG_SP,sp)
 original=[rnd.getrandbits(32) for r in regs];original[0]=0 if case%2==0 else original[0]
 for r,v in zip(regs,original):u.reg_write(r,v)
 mmio=bytes(rnd.getrandbits(8) for _ in range(4096));u.mem_write(0x58120000,mmio);output=[]
 def hook(c,a,n,d):
  if a==0x503f4d28:c.emu_stop()
 def write(c,access,a,size,value,data):
  if a==0x59000000:assert size==1;output.append(value)
 u.hook_add(UC_HOOK_CODE,hook);u.hook_add(UC_HOOK_MEM_WRITE,write);u.emu_start(int(syms['mmc_dma'],16),0,count=30000)
 word=lambda off:struct.unpack_from('<I',mmio,off)[0]
 expected=bytes([0xc0])+f'M D {original[0]:08x} {word(0x64):08x}\n'.encode()
 for ch in range(8):
  values=[ch]+[word(0x300+ch*0x40+off) for off in [4,8,0x14,0x18,0x1c,0x20,0x24,0x28,0x2c]]
  expected+=bytes([0xc0])+('M C '+''.join(f'{v:08x} ' for v in values)+'\n').encode()
 expected+=b'\n'
 assert bytes(output)==expected,(bytes(output),expected)
 assert [u.reg_read(r) for r in regs]==original and u.reg_read(UC_ARM_REG_SP)==sp and u.reg_read(UC_ARM_REG_PC)==0x503f4d28
 expected_flags=(flags&0x0fffffff)|0x20000000|(0x40000000 if original[0]==0 else original[0]&0x80000000)
 assert u.reg_read(UC_ARM_REG_CPSR)==expected_flags
 assert bytes(u.mem_read(0x58120000,4096))==mmio
print('PASS 384 observer cases including all8 DMA programming banks, exact output, state preservation, original CMP flags and read-only register access')
