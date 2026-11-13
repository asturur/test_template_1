from pathlib import Path
import ast,hashlib,struct,sys,json
sys.path.insert(0,'tools');import service_firmware
from build_virtual_sim import rules,decode16
p=Path('scratch/rf-board-qualification-20261113');s=(p/'observer.py').read_text();tree=ast.parse(s);assign={x.targets[0].id:x for x in tree.body if isinstance(x,ast.Assign) and isinstance(x.targets[0],ast.Name)};records=[];report=ast.literal_eval(assign['report'].value)
raw=bytearray(b'\xff'*service_firmware.BACKING_SIZE)
for kind,spec in service_firmware.PROFILES.items():
 source=Path('firmware/NEM-04 v.04.03 N-GAGE')/spec[0];service_firmware.apply(raw,service_firmware.parse(source.read_bytes(),kind),kind)
assert hashlib.sha256(raw).hexdigest()==report['original_rom_sha256']
b=(p/'assert/trace.bin').read_bytes();assert len(b)%4==0 and len(b)<=0x300
extra=[(0x316d00+i,0,struct.unpack_from('<I',b,i)[0]) for i in range(0,len(b),4)]
addr,target=0x516c74e8,0x51716d00;delta=target-addr-8;assert delta%4==0 and -(1<<25)<=delta<(1<<25);branch=0xea000000|((delta>>2)&0xffffff);assert addr+8+((branch&0xffffff)<<2)==target
extra.append((0x2c74e8,0xeaf76cc5,branch));records=[r for r in records if r[0] not in range(0x8f20,0x8f30)]+extra
assert len({x[0] for x in records})==len(records)
for off,old,new in records:
 assert struct.unpack_from('<I',raw,off)[0]==old,hex(off)
 struct.pack_into('<I',raw,off,new)
view=bytearray(raw);rule=rules()
for a in range(0xa000,0x2b3000,2):struct.pack_into('<H',view,a,decode16(struct.unpack_from('<H',raw,a)[0],a,rule))
old=bytes(raw[0x8f20:0x8f30]);digest=hashlib.md5(view[0x9000:0x11b5000]).digest()
for i in range(0,16,4):records.append((0x8f20+i,int.from_bytes(old[i:i+4],'little'),int.from_bytes(digest[i:i+4],'little')))
raw[0x8f20:0x8f30]=digest;report.update(records=len(records),instrumented_rom_sha256=hashlib.sha256(raw).hexdigest(),diagnostic_cpu_view_md5=digest.hex(),native_assert_observation=True,observer_sha256=hashlib.sha256(b).hexdigest(),scope='Native assertion and CPU-visible result observation only; RF/exit/SIM/DOS hooks omitted',functional_startup_substitutions=False)
lines=s.splitlines()
for name,value in [('records',sorted(records)),('report',report)]:
 node=assign[name];assert node.lineno==node.end_lineno;lines[node.lineno-1]=name+'='+repr(value)
(p/'assert/observer.py').write_text('\n'.join(lines)+'\n');(p/'assert/manifest.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
