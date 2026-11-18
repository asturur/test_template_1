import hashlib,inspect,json,struct,sys
from pathlib import Path
sys.path.insert(0,'tools')
import prepare_native_observer as native
p=Path('scratch/calendar-idle-run-20261114');blob=(p/'trace.bin').read_bytes();assert len(blob)<=4096 and len(blob)%4==0
extra=[(0x11b8000+i,0xffffffff,struct.unpack_from('<I',blob,i)[0]) for i in range(0,len(blob),4)]
syms={a[2]:int(a[0],16) for l in (p/'symbols.txt').read_text().splitlines() if len(a:=l.split())==3}
for name,addr in [('start',0x50399d70),('run',0x50399dac),('ready',0x50399da4)]:
 extra.append((addr-0x50000000,0xe8bd4010 if name=='ready' else 0xe92d4010,0xea000000|(((syms[name+'_trace']-addr-8)//4)&0xffffff)))
s=inspect.getsource(native.prepare);needle='records = runtime.exit_records(payload, slow_wait=slow_wait)';assert s.count(needle)==1;s=s.replace(needle,needle+'\n    records += extra_records')
ns=dict(vars(native),extra_records=extra);exec(compile(s,'prepare_calendar','exec'),ns)
r=ns['prepare'](p/'prepared',False);r['calendar_trace_sha256']=hashlib.sha256(blob).hexdigest();r['idle_trace']='Global CIdle Start/RunL observation only in USER mode and callbacks within AgnModel/Agnsynca/Agndasvr or Calendar; native debug print; original first push and body preserved';r['scope']='Observe scheduling versus execution, no functional startup substitutions, no kernel printing, no direct MMIO, no idle callback substitution';(p/'manifest.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r))
