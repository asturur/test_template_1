from pathlib import Path
import subprocess,struct,inspect,json,hashlib,sys
sys.path.insert(0,'tools')
import prepare_native_observer as native
p=Path('scratch/mmc-native-20261114')
(p/'link.ld').write_text('debug_print = 0x503b409c; SECTIONS { .text 0x511bd000 : { *(.text*) } /DISCARD/ : { *(.ARM.attributes) *(.comment) *(.note*) } }')
for cmd in [ ['arm-none-eabi-gcc','-c','-mcpu=arm920t',str(p/'trace.S'),'-o',str(p/'trace.o')],['arm-none-eabi-ld','-T',str(p/'link.ld'),str(p/'trace.o'),'-o',str(p/'trace.elf')],['arm-none-eabi-objcopy','-O','binary',str(p/'trace.elf'),str(p/'trace.bin')]]:subprocess.run(cmd,check=True)
b=(p/'trace.bin').read_bytes();assert len(b)%4==0 and len(b)<4096
syms={x[2]:int(x[0],16) for l in subprocess.check_output(['arm-none-eabi-nm',str(p/'trace.elf')],text=True).splitlines() if len(x:=l.split())==3}
extra=[(0x11bd000+i,0xffffffff,int.from_bytes(b[i:i+4],'little')) for i in range(0,len(b),4)]
for a,old,name in [(0x503f4708,0xe59538b8,'mmc_begin'),(0x503f5074,0xe3a02000,'mmc_end'),(0x503f508c,0xe28dd008,'mmc_error'),(0x503f556c,0xe1a00005,'mmc_flags'),(0x503f5300,0xe1a04003,'mmc_status')]:
 target=syms[name];assert -(1<<25)<=target-a-8<(1<<25)
 extra.append((a-0x50000000,old,0xea000000|(((target-a-8)//4)&0xffffff)))
native.runtime.EXIT_TRACE_SHA=hashlib.sha256(b).hexdigest()
s=inspect.getsource(native.prepare).replace('records = runtime.exit_records(payload, slow_wait=slow_wait)','records = list(extra_records)')
ns=dict(vars(native),extra_records=extra);exec(compile(s,'mmc-observer','exec'),ns)
r=ns['prepare'](p/'prepared',False);r.update(observer_sha256=hashlib.sha256(b).hexdigest(),scope='Original MMC request/response diagnostics only; no substituted response or deadline',hooks={n:hex(syms[n]) for n in ('mmc_begin','mmc_end','mmc_error','mmc_flags','mmc_status')})
(p/'manifest.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r))
