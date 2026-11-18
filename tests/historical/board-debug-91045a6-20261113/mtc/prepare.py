import hashlib,inspect,json,struct,sys
from pathlib import Path
sys.path.insert(0,'tools')
import prepare_native_observer as native
from build_virtual_sim import encode16,decode16
p=Path('scratch/board-debug-91045a6-20261113/mtc')
b=(p/'trace.bin').read_bytes();assert len(b)%4==0 and len(b)<1024
extra=[(0x11bd000+i,0xffffffff,struct.unpack_from('<I',b,i)[0]) for i in range(0,len(b),4)]
# Enumerate exact original Thumb BL call sites, preserving neighboring halfwords.
source=Path('firmware/THC N-Gage ROM Dump/ngage-gsmstuff-0x5149D280.dll').read_bytes()[96:]
origin=0x5149d280
patches={};sites=[]
for addr in range(0x51599000,0x5159b000,2):
    off=addr-origin;hi,lo=struct.unpack_from('<HH',source,off)
    if hi&0xf800 != 0xf000 or lo&0xf800 != 0xf800:continue
    delta=((hi&0x7ff)<<12)|((lo&0x7ff)<<1)
    if delta&(1<<22):delta-=1<<23
    if addr+4+delta!=0x5159a198:continue
    sites.append(hex(addr));delta=0x511bd000-addr-4
    encoded=struct.pack('<HH',0xf000|((delta>>12)&0x7ff),0xf800|((delta>>1)&0x7ff))
    for j,v in enumerate(encoded):patches[addr+j]=v
assert len(sites)==24,sites
for addr in sorted({a&~3 for a in patches}):
    old=source[addr-origin:addr-origin+4];new=bytes(patches.get(addr+j,old[j]) for j in range(4))
    extra.append((addr-0x51400000,int.from_bytes(old,'little'),int.from_bytes(new,'little')))
sim=json.loads(Path('build/firmware-overlays/sim-trace/trace.json').read_text())
extra += [tuple(x) for x in sim['records']]
s=inspect.getsource(native.prepare)
needle='records = runtime.exit_records(payload, slow_wait=slow_wait)';assert s.count(needle)==1;s=s.replace(needle,needle+'\n    records += extra_records')
needle='    for offset, old, new in records:\n        if struct.unpack_from(\'<I\',raw,offset)[0] != old:'
assert s.count(needle)==1
s=s.replace(needle,'''    # Convert encrypted-region CPU-view records into exact raw backing words.
    converted=[]
    for offset,old,new in records:
        if 0xa000<=offset and offset+4<=0x2b3000:
            original_raw=struct.unpack_from('<I',raw,offset)[0]
            for i in (0,2):
                assert decode16((original_raw>>(i*8))&0xffff,offset+i,rule)==((old>>(i*8))&0xffff)
            encoded=sum(encode16((new>>(i*8))&0xffff,offset+i,rule)<<(i*8) for i in (0,2))
            converted.append((offset,original_raw,encoded))
        else:converted.append((offset,old,new))
    records=converted
'''+needle)
ns=dict(vars(native),extra_records=extra,encode16=encode16)
exec(compile(s,'lookup-observer','exec'),ns)
r=ns['prepare'](p/'prepared',False);r['mtc_sha256']=hashlib.sha256(b).hexdigest();r['scope']='Native MTC messages and state; original function tailcall; no substitutions'
r['call_sites']=sites
(p/'manifest.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r))
