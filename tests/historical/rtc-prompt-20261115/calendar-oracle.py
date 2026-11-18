from pathlib import Path
import struct,hashlib,json
from unicorn import Uc,UC_ARCH_ARM,UC_MODE_ARM
from unicorn.arm_const import UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_SP,UC_ARM_REG_LR,UC_ARM_REG_CPSR,UC_ARM_REG_PC
b=Path('build/firmware/nem4-factory/core.bin').read_bytes();assert hashlib.sha256(b).hexdigest()=='be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524'
result=[]
for value in [63209667300000000,63209667240000000,62168256000000000,63113904000000000]:
 u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x50000000,0x1400000);u.mem_write(0x50000000,b);u.mem_map(0x80000000,0x20000);u.mem_write(0x80001000,struct.pack('<Q',value))
 for reg,x in [(UC_ARM_REG_R0,0x80002000),(UC_ARM_REG_R1,0x80001000),(UC_ARM_REG_SP,0x8001f000),(UC_ARM_REG_LR,0x80003000),(UC_ARM_REG_CPSR,0x13)]:u.reg_write(reg,x)
 u.emu_start(0x503bd384,0x80003000,count=100000);assert u.reg_read(UC_ARM_REG_PC)==0x80003000
 row=dict(ttime=value,native_datetime_fields=list(struct.unpack('<7i',u.mem_read(0x80002000,28))));result.append(row);print(row)
Path('scratch/rtc-prompt-20261115/calendar-oracle.json').write_text(json.dumps(result,indent=2)+'\n')
