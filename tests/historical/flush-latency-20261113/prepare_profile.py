"""Prepare scoped EStor observer using the maintained fresh-Hold/checksum guards."""
import hashlib,inspect,json,struct,sys
from pathlib import Path
sys.path.insert(0,'tools')
import prepare_native_observer as native
root=Path('scratch/flush-latency-20261113')
payload=(root/'profile_trace.bin').read_bytes()
import subprocess
symbols={f[2]:int(f[0],16) for l in subprocess.check_output(['arm-none-eabi-nm',str(root/'profile_trace.elf')],text=True).splitlines() if len(f:=l.split())==3}
assert len(payload)<=4096 and len(payload)%4==0
assert hashlib.sha256(payload).hexdigest()=='10e80e43fd35ee0fb9492b1eb448b17f35393fba7ad80ff900a122b1614e4b2a'
records=[(0x11ba000+i,0xffffffff,struct.unpack_from('<I',payload,i)[0]) for i in range(0,len(payload),4)]
records += [(0xa14dd8,0x50463884,symbols['count_slot']), (0xa14df0,0x50463a08,symbols['dbopen_slot']), (0xa14f70,0x508c32d0,symbols['store_slot'])]
source=inspect.getsource(native.prepare)
needle='records = runtime.exit_records(payload, slow_wait=slow_wait)'
assert source.count(needle)==1
source=source.replace(needle,needle+'\n    records += extra_records')
namespace=dict(vars(native),extra_records=records)
exec(compile(source,'prepare_io.py','exec'),namespace)
report=namespace['prepare'](root/'profile-prepared',False)
report['io_trace_sha256']=hashlib.sha256(payload).hexdigest()
report['scope']='ProfileEngine native CountL, DBOpen and StoreOpen results only; original implementations unchanged'
(root/'profile-manifest.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
