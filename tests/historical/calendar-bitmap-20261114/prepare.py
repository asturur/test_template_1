import hashlib,inspect,json,struct,sys
from pathlib import Path
sys.path.insert(0,'tools')
import prepare_native_observer as native
p=Path('scratch/calendar-bitmap-20261114');blob=(p/'trace.bin').read_bytes();assert len(blob)<=4096 and len(blob)%4==0
extra=[(0x11b8000+i,0xffffffff,struct.unpack_from('<I',blob,i)[0]) for i in range(0,len(blob),4)]
syms={a[2]:int(a[0],16) for l in (p/'symbols.txt').read_text().splitlines() if len(a:=l.split())==3}
for name,addr,old in [('window',0x50400544,0xe92d4030),('header12',0x50400640,0xe92d4010),('header16',0x50400668,0xe92d4010),('line',0x50400efc,0xe92d4070)]:
    extra.append((addr-0x50000000,old,0xea000000|(((syms[name+'_trace']-addr-8)//4)&0xffffff)))

rom=Path('build/firmware/nem4-factory/core.bin').read_bytes()
for name,addr in [('pixel',0x50558f8c),('scan',0x505598a4),('stretch',0x50559f20)]:
    thunk=bytes.fromhex('08b4014b1847c046')+struct.pack('<I',syms[name+'_trace'])
    for i in range(0,12,4):extra.append((addr-0x50000000+i,struct.unpack_from('<I',rom,addr-0x50000000+i)[0],struct.unpack_from('<I',thunk,i)[0]))
s=inspect.getsource(native.prepare);needle='records = runtime.exit_records(payload, slow_wait=slow_wait)';assert s.count(needle)==1;s=s.replace(needle,needle+'\n    records += extra_records')
ns=dict(vars(native),extra_records=extra);exec(compile(s,'prepare_calendar','exec'),ns)
r=ns['prepare'](p/'prepared',False);r['calendar_trace_sha256']=hashlib.sha256(blob).hexdigest();r['bitmap_trace']='CBitwiseBitmap GetPixel/GetScanLine/StretchScanLine metadata only at y multiples32; pixel calls additionally x0; exact six displaced Thumb instructions replayed with all GPR/flags restored at continuation; no services'
r['scope']='Native LCD window/header12/header16 and row entry observations; exact original functions execute after full register/flags restoration; line descriptor and one originally readable source pixel sampled; direct existing VA59000000 byte-output only; no debug service/SWI or functional substitutions';(p/'manifest.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r))
