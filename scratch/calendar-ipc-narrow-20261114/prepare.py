import hashlib,inspect,json,struct,sys
from pathlib import Path
sys.path.insert(0,'tools')
import prepare_native_observer as native
p=Path('scratch/calendar-ipc-narrow-20261114');blob=(p/'trace.bin').read_bytes();assert len(blob)<=4096 and len(blob)%4==0
extra=[(0x11b8000+i,0xffffffff,struct.unpack_from('<I',blob,i)[0]) for i in range(0,len(blob),4)]
extra.append((0x85bab4,0x503cbaa8,0x511b8000))

s=inspect.getsource(native.prepare);needle='records = runtime.exit_records(payload, slow_wait=slow_wait)';assert s.count(needle)==1;s=s.replace(needle,needle+'\n    records += extra_records')
ns=dict(vars(native),extra_records=extra);exec(compile(s,'prepare_calendar','exec'),ns)
r=ns['prepare'](p/'prepared',False);r['calendar_trace_sha256']=hashlib.sha256(blob).hexdigest();r['scope']='AGN-model-only sync IPC import thunk; no FullName/kernel name calls, no global sync entry hook; exact original sync body';(p/'manifest.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r))
