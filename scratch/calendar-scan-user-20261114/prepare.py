import hashlib,inspect,json,struct,sys
from pathlib import Path
sys.path.insert(0,'tools')
import prepare_native_observer as native
p=Path('scratch/calendar-scan-user-20261114');blob=(p/'trace.bin').read_bytes();assert len(blob)<=4096 and len(blob)%4==0
extra=[(0x11b8000+i,0xffffffff,struct.unpack_from('<I',blob,i)[0]) for i in range(0,len(blob),4)]
syms={a[2]:int(a[0],16) for l in (p/'symbols.txt').read_text().splitlines() if len(a:=l.split())==3}
rom=Path('build/firmware/nem4-factory/core.bin').read_bytes()
for name,addr in [('scan',0x505598a4)]:
    thunk=bytes.fromhex('08b4014b1847c046')+struct.pack('<I',syms[name+'_trace'])
    for i in range(0,12,4):extra.append((addr-0x50000000+i,struct.unpack_from('<I',rom,addr-0x50000000+i)[0],struct.unpack_from('<I',thunk,i)[0]))
s=inspect.getsource(native.prepare);needle='records = runtime.exit_records(payload, slow_wait=slow_wait)';assert s.count(needle)==1;s=s.replace(needle,needle+'\n    records += extra_records')
ns=dict(vars(native),extra_records=extra);exec(compile(s,'prepare_calendar','exec'),ns)
r=ns['prepare'](p/'prepared',False);r['calendar_trace_sha256']=hashlib.sha256(blob).hexdigest();r['bitmap_trace']='Only CBitwiseBitmap GetScanLine at y multiples32; metadata via native USER RDebug::Print service. All original GPRs/flags and six displaced Thumb instructions restored before continuation. No functional substitution';r['scope']='USER bitmap observer only, no LCD/kernel hooks or direct MMIO. Native debug Print ABI spied in36 Unicorn cases; board qualification pending';(p/'manifest.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r))
