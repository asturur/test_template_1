from pathlib import Path
import hashlib,json,struct
from unicorn import Uc,UC_ARCH_ARM,UC_MODE_ARM,UC_HOOK_CODE
from unicorn.arm_const import UC_ARM_REG_R0,UC_ARM_REG_R1,UC_ARM_REG_R2,UC_ARM_REG_R3,UC_ARM_REG_R6,UC_ARM_REG_SP,UC_ARM_REG_LR,UC_ARM_REG_PC,UC_ARM_REG_CPSR
P=Path(__file__).resolve().parent
rom=Path('build/firmware/nem4-factory/core.bin').read_bytes();assert hashlib.sha256(rom).hexdigest()=='be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524'
source=Path('firmware/THC N-Gage ROM Dump/ngage-gsmstuff-0x5149D280.dll').read_bytes();assert hashlib.sha256(source).hexdigest()=='e5870e918c90d9c7a6403eb0ee305d174e906aeae0a7fa8069e85a18aeec7aa1';nos=source[96:]
records=json.loads(Path('docs/evidence/rtc-prompt-20261115.json').read_text())['captured_pmm']
def values(name):
 rows=records[name]['candidate_active_records'];result=[]
 for rec in range(3):
  a=[x for x in rows if x['table']=='0xd4' and x['record']==rec and x['state']=='0xf4'];assert len(a)==1
  result.append(int.from_bytes(bytes.fromhex(a[0]['payload']),'little'))
 return result
cases=[('live',values('live-pmm.bin'),False),('saved',values('saved-pmm.vhd'),False)]
a=values('live-pmm.bin');cases+=[('equal_nonzero_control',[a[0],a[0],0],True),('equal_zero_control',[0,0,0],False),('unrelated_alarm_control',[a[0],a[1],a[0]],False)]
result=dict(status='INCOMPLETE',original_instructions_modified=False,service_factory_modeled=True,scope='Original NOS argument forwarding and ecust PMM acceptance guard; not full boot or native date restoration',cases=[])
try:
 for name,vals,accepted in cases:
  u=Uc(UC_ARCH_ARM,UC_MODE_ARM);u.mem_map(0x50000000,0x2000000);u.mem_write(0x50000000,rom);u.mem_write(0x5149d280,nos);u.mem_map(0x80000000,0x20000)
  def put(a,n):u.mem_write(a,struct.pack('<I',n))
  put(0x8000cea4,0x80000200);put(0x80000200,0x80000400);put(0x80000434,0x514a4d64)
  put(0x80000208,0x80000600);put(0x80000600,0x80000800);put(0x80000820,0x5034e444)
  put(0x8000063c,1);put(0x8000060c,1)
  put(0x80000a00,0x80000c00);put(0x80000d00,0x80000e00);u.mem_write(0x80000e00,bytes.fromhex('0100a0e31eff2fe1'))
  for i,n in enumerate(vals):u.mem_write(0x80001000+16*i,struct.pack('<Q',n))
  for reg,n in [(UC_ARM_REG_SP,0x8001e000),(UC_ARM_REG_LR,0x80001080),(UC_ARM_REG_CPSR,0x13),(UC_ARM_REG_R0,1),(UC_ARM_REG_R1,0x80001020),(UC_ARM_REG_R2,0x80001000),(UC_ARM_REG_R3,0x80001010)]:u.reg_write(reg,n)
  seen={};steps=[0]
  def code(uc,pc,size,_):
   steps[0]+=1
   if pc==0x5034e138:
    sp=uc.reg_read(UC_ARM_REG_SP)
    seen['ecust_arguments']=[uc.reg_read(UC_ARM_REG_R1)|(uc.reg_read(UC_ARM_REG_R2)<<32),uc.reg_read(UC_ARM_REG_R3)|(int.from_bytes(uc.mem_read(sp,4),'little')<<32),int.from_bytes(uc.mem_read(sp+4,8),'little')]
   if pc==0x503501dc:uc.reg_write(UC_ARM_REG_R0,0x80000a00);uc.reg_write(UC_ARM_REG_PC,uc.reg_read(UC_ARM_REG_LR))
   if pc in (0x5034e1d0,0x5034e2b0):seen['stop_pc']=pc;uc.emu_stop()
  u.hook_add(UC_HOOK_CODE,code);u.emu_start(0x516c77b5,0,count=20000)
  assert seen['ecust_arguments']==vals,seen
  assert seen.get('stop_pc')==(0x5034e1d0 if accepted else 0x5034e2b0),seen
  valid=int.from_bytes(u.mem_read(0x8000063c,4),'little');state=int.from_bytes(u.mem_read(0x8000060c,4),'little');assert valid==int(accepted) and state==(1 if accepted else 9),(valid,state)
  result['cases'].append(dict(name=name,records=vals,accepted=accepted,valid=valid,state=state,instructions=steps[0],trace=seen));print('PASS',name,'valid',valid,'state',state,flush=True)
 result['status']='PASS'
finally:(P/'restore-oracle.json').write_text(json.dumps(result,indent=2)+'\n')
