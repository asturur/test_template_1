from pathlib import Path
import struct,json,re,sys
core=Path('build/firmware/nem4-factory/core.bin').read_bytes();b=Path('firmware/disk_dump/Z/System/Data/Avkon.mbm').read_bytes();n=struct.unpack_from('<I',b,4)[0];offs=struct.unpack_from('<%dI'%n,b,8);assets={};base=core.find(b);assert base>=0,'Exact whole Avkon.mbm absent from original core'
for idx,o in enumerate(offs):
 v=struct.unpack_from('<15I',b,o)
 if v[7:9] not in [(30,40),(120,10)]:continue
 assets[f'{0x50000000+base+o:08x}']=[dict(index=idx,width=v[7],height=v[8],depth=v[11],colour=v[12],compression=v[14],file_offset=hex(o))]
p=Path(sys.argv[1]);r=json.loads(p.read_text());seen={}
for t in r['bitmap']:
 m=re.fullmatch(r'D BITMAP=([0-9a-f]{8}) parent=([0-9a-f]{8}) length=([0-9a-f]{8})',t)
 if not m:continue
 key=m.group(1);x=seen.setdefault(key,dict(count=0,parents={},lengths={},exact_native_header_candidates=assets.get(key,[])));x['count']+=1
 for field,val in [('parents',m.group(2)),('lengths',m.group(3))]:x[field][val]=x[field].get(val,0)+1
out=dict(reader_gaps=r['reader_gaps'],snapshots=r['snapshots'],kernel_stop_samples=r['kernel_stop_samples'],assets=seen)
p.with_name(p.stem+'.assets.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out,indent=2))
