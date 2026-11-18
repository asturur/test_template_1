"""Prepare scoped EStor observer using the maintained fresh-Hold/checksum guards."""
import hashlib,inspect,json,struct,sys
from pathlib import Path
sys.path.insert(0,'tools')
import prepare_native_observer as native
root=Path('scratch/flush-latency-20261113')
payload=(root/'io_trace.bin').read_bytes()
import subprocess
symbols={f[2]:int(f[0],16) for l in subprocess.check_output(['arm-none-eabi-nm',str(root/'io_trace.elf')],text=True).splitlines() if len(f:=l.split())==3}
assert len(payload)<=4096 and len(payload)%4==0
assert hashlib.sha256(payload).hexdigest()=='101371b03c28fe6b19a1606143cfbd9c72785dd577fb74cd8e54a0e3c125d1ab'
records=[(0x11b8000+i,0xffffffff,struct.unpack_from('<I',payload,i)[0]) for i in range(0,len(payload),4)]
records += [(0x8c1c28,0x503e3dd0,0x511b8000),(0x8c1c04,0x503e4020,0x511b8004), (0x8c1bc8,0x503e3eec,symbols['open_slot']), (0x8c1be8,0x503e3f64,symbols['replace_slot'])]
source=inspect.getsource(native.prepare)
needle='records = runtime.exit_records(payload, slow_wait=slow_wait)'
assert source.count(needle)==1
source=source.replace(needle,needle+'\n    records += extra_records')
namespace=dict(vars(native),extra_records=records)
exec(compile(source,'prepare_io.py','exec'),namespace)
report=namespace['prepare'](root/'prepared',False)
report['io_trace_sha256']=hashlib.sha256(payload).hexdigest()
report['scope']='Phone-scoped EStor RFile Open/Replace/Write/Flush imports; original implementations unchanged'
(root/'io-manifest.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
