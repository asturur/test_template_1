"""Build observation-only RF veneers and fresh-Hold guarded board installer.

Run from the repository root. No connection or installation is performed.
The fixture mocks native callees to verify arguments/flags/SP/return, not RF
success. Real request/reply behavior is covered separately by native_mdi.
"""
from pathlib import Path
import subprocess,struct,inspect,sys,json
p=Path('scratch/rf-timeout-20261113');old=Path('scratch/board-debug-91045a6-20261113/mtc')
(p/'link.ld').write_text('ENTRY(rf_send)\nSECTIONS { .text 0x51716a00 : { *(.text*) } /DISCARD/ : { *(.ARM.attributes) *(.comment) *(.note*) } }\n')
program=(old/'program.S').read_text().replace('0x511bd001','0x51716a01').replace('mov r1,#6','ldr r1,=0x80000000').replace('cmp r1,#6','cmp r1,r2')
(p/'program.S').write_text(program)
for name in ['trace','program']:
 subprocess.run(['arm-none-eabi-gcc','-c','-march=armv4t',str(p/(name+'.S')),'-o',str(p/(name+'.o'))],check=True)
 subprocess.run(['arm-none-eabi-ld','-T',str(p/'link.ld') if name=='trace' else str(old/'test.ld'),str(p/(name+'.o')),'-o',str(p/(name+'.elf'))],check=True)
 subprocess.run(['arm-none-eabi-objcopy','-O','binary',str(p/(name+'.elf')),str(p/(name+'.bin'))],check=True)
 b=(p/(name+'.bin')).read_bytes().ljust(4096 if name=='trace' else 2048,b'\0')
 (p/(name+'.hex')).write_text(''.join(f'{int.from_bytes(b[i:i+4],"little"):08x}\n' for i in range(0,len(b),4)))
expected=b'R1 00000064 80000000 80000000 00000003 00000044 00000000 00000000 00000000 00000000\n'
(p/'expected.hex').write_text(''.join(f'{v:02x}\n' for v in expected))
s=(old/'tb.v').read_text().replace(str(old),str(p)).replace('511bd000','51716a00').replace('511be000','51717a00').replace('0:164',f'0:{len(expected)-1}').replace('165',str(len(expected))).replace('5159a198','514ba3f0').replace('5159a19c','514ba3f4').replace('5159a1a0','514ba3f8')
s=s.replace('PASS ZAP MTC observer:', 'PASS ZAP RF observer:')
(p/'tb.v').write_text(s)
# Build realistic per-entry ABI fixtures; one CPU executable selects each image.
for tag,target in [(i,0x51716a01+12*(i-1)) for i in range(1,9)]:
 t=program.replace('0x51716a01',hex(target))
 if tag==2:
  t=t.replace('ldr r2,=0x80000000','mov r2,#6').replace('cmp r1,r2','ldr r0,=0x80000000\n cmp r1,r0').replace('cmp r2,r0','cmp r2,#6').replace('str r0,[r2]','ldr r12,=0x80000000\n str r0,[r12]')
 (p/'case.S').write_text(t)
 for cmd in [['arm-none-eabi-gcc','-c','-march=armv4t',str(p/'case.S'),'-o',str(p/'case.o')],['arm-none-eabi-ld','-T',str(old/'test.ld'),str(p/'case.o'),'-o',str(p/'case.elf')],['arm-none-eabi-objcopy','-O','binary',str(p/'case.elf'),str(p/'case.bin')]]:subprocess.run(cmd,check=True)
 b=(p/'case.bin').read_bytes().ljust(2048,b'\0')
 (p/f'program-{tag}.hex').write_text(''.join(f'{int.from_bytes(b[i:i+4],"little"):08x}\n' for i in range(0,len(b),4)))
 # ARM return offset remains 44, even when the mock native body changes.
 e=f'R{tag} 00000064 80000000 {"00000006" if tag==2 else "80000000"} 00000003 00000044 '+('00'*(12 if tag==2 else 0 if tag>=6 else 4))+' 00000000 00000000 00000000 00000000\n'
 (p/f'expected-{tag}.hex').write_text(''.join(f'{v:02x}\n' for v in e.encode()))
s=(p/'tb.v').read_text().replace(f'0:{len(expected)-1}','0:255').replace('printed!='+str(len(expected)),'printed!=expected_length').replace('printed>='+str(len(expected)),'printed>=expected_length')
s=s.replace('integer printed=0;','integer printed=0; integer tag,expected_length,wait_cycles; reg [2047:0] name;')
s=s.replace('delay_count==WAIT_CYCLES','delay_count==wait_cycles')
s=s.replace('address==32\'h514ba3f0',"(address==32'h514ba3f0||address==32'h515bf550||address==32'h515920d0)").replace('address==32\'h514ba3f4',"(address==32'h514ba3f4||address==32'h515bf554||address==32'h515920d4)").replace('address==32\'h514ba3f8',"(address==32'h514ba3f8||address==32'h515bf558||address==32'h515920d8)")
s=s.replace('initial begin','initial begin\n if(!$value$plusargs("tag=%d",tag))tag=1;\n if(!$value$plusargs("wait=%d",wait_cycles))wait_cycles=0;\n expected_length=tag==2 ? 109 : tag>=6 ? 85 : 93;')
s=s.replace('$readmemh("scratch/rf-timeout-20261113/program.hex",program_words);','$sformat(name,"scratch/rf-timeout-20261113/program-%0d.hex",tag); $readmemh(name,program_words);').replace('$readmemh("scratch/rf-timeout-20261113/expected.hex",expected);','$sformat(name,"scratch/rf-timeout-20261113/expected-%0d.hex",tag); $readmemh(name,expected);')
for offset in [0,4,8]:
 a=0x514ba3f0+offset
 for target in [0x5164ae78,0x5164b3a4,0x5164b20c,0x516a60c0]:
  s=s.replace(f"address==32'h{a:08x}",f"address==32'h{a:08x}||address==32'h{target+offset:08x}")
s=s.replace('WAIT_CYCLES);','wait_cycles);')
(p/'tb.v').write_text(s)
sys.path.insert(0,'tools');import prepare_native_observer as native
from build_virtual_sim import encode16,decode16
b=(p/'trace.bin').read_bytes();assert len(b)%4==0 and len(b)<=0x600;extra=[(0x316a00+i,0,struct.unpack_from('<I',b,i)[0]) for i in range(0,len(b),4)]
source=Path('firmware/THC N-Gage ROM Dump/ngage-gsmstuff-0x5149D280.dll').read_bytes()[96:];base=0x5149d280
symbols={x[2]:int(x[0],16) for line in subprocess.check_output(['arm-none-eabi-nm',str(p/'trace.elf')],text=True).splitlines() if len(x:=line.split())==3}
patches={}
for addr,name in [(0x5164b4ee,'rf_send'),(0x514c4904,'mdi_write'),(0x51592038,'rf_receive'),(0x516a60fc,'rf_start'),(0x51591d28,'info_mgr'),(0x51591d64,'info_mgr'),(0x51591ff4,'info_mgr'),(0x5164af5e,'rf_builder'),(0x5164b03e,'rf_builder'),(0x5164b4c8,'rf_route')]:
 d=(symbols[name]&~1)-addr-4;assert -(1<<22)<=d<(1<<22),hex(addr);new=struct.pack('<HH',0xf000|((d>>12)&0x7ff),0xf800|((d>>1)&0x7ff))
 hi,lo=struct.unpack('<HH',new)
 decoded=((hi&0x7ff)<<12)|((lo&0x7ff)<<1)
 if decoded&0x400000:decoded-=0x800000
 assert addr+4+decoded==(symbols[name]&~1)
 for j,v in enumerate(new):patches[addr+j]=v
for addr in sorted({a&~3 for a in patches}):
 oldword=source[addr-base:addr-base+4];new=bytes(patches.get(addr+j,oldword[j]) for j in range(4));extra.append((addr-0x51400000,int.from_bytes(oldword,'little'),int.from_bytes(new,'little')))
# Keep the native test registry entirely unchanged.
# Previously qualified position-independent MTC probe, relocated by 4 KiB.
b=(old/'trace.bin').read_bytes()
extra += [(0x11be000+i,0xffffffff,struct.unpack_from('<I',b,i)[0]) for i in range(0,len(b),4)]
for addr in range(0x51599000,0x5159b000,2):
 hi,lo=struct.unpack_from('<HH',source,addr-base)
 if hi&0xf800!=0xf000 or lo&0xf800!=0xf800:continue
 d=((hi&0x7ff)<<12)|((lo&0x7ff)<<1)
 if d&0x400000:d-=0x800000
 if addr+4+d!=0x5159a198:continue
 d=0x511be000-addr-4;assert -(1<<22)<=d<(1<<22);new=struct.pack('<HH',0xf000|((d>>12)&0x7ff),0xf800|((d>>1)&0x7ff))
 # Some call sites are halfword-aligned; merge exact CPU-view words.
 for j,v in enumerate(new):patches[addr+j]=v
# Rebuild all call-site words including MTC.
extra=[x for x in extra if not (0x9d280<=x[0]<0x2b3000)]
for addr in sorted({a&~3 for a in patches}):
 oldword=source[addr-base:addr-base+4];new=bytes(patches.get(addr+j,oldword[j]) for j in range(4));extra.append((addr-0x51400000,int.from_bytes(oldword,'little'),int.from_bytes(new,'little')))
for name in ['sim','dos']:
 extra += [tuple(x) for x in json.loads(Path(f'build/firmware-overlays/{name}-trace/trace.json').read_text())['records']]
s=inspect.getsource(native.prepare).replace('records = runtime.exit_records(payload, slow_wait=slow_wait)','records = runtime.exit_records(payload, slow_wait=slow_wait)\n    records += extra_records')
needle="    for offset, old, new in records:\n        if struct.unpack_from('<I',raw,offset)[0] != old:"
s=s.replace(needle,"""    converted=[]
    for offset,old,new in records:
        if 0xa000<=offset and offset+4<=0x2b3000:
            original_raw=struct.unpack_from('<I',raw,offset)[0]
            for i in (0,2):assert decode16((original_raw>>(i*8))&0xffff,offset+i,rule)==((old>>(i*8))&0xffff)
            encoded=sum(encode16((new>>(i*8))&0xffff,offset+i,rule)<<(i*8) for i in (0,2))
            converted.append((offset,original_raw,encoded))
        else:converted.append((offset,old,new))
    records=converted
"""+needle)
ns=dict(vars(native),extra_records=extra,encode16=encode16);exec(compile(s,'rf-observer','exec'),ns)
print(json.dumps(ns['prepare'](p/'prepared',False),indent=2))
