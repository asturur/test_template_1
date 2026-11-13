"""Extract untouched original MDI ring routines; generated instructions stay private."""
from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[3]
out=root/'build/sim/unit-native-mdi'
rom=(root/'firmware/THC N-Gage ROM Dump/ngage-gsmstuff-0x5149D280.dll').read_bytes()
sha=hashlib.sha256(rom).hexdigest()
assert sha=='e5870e918c90d9c7a6403eb0ee305d174e906aeae0a7fa8069e85a18aeec7aa1'
body=rom[96:]
for name,data,size in (('original',body[0x515bf000-0x5149d280:0x515c0000-0x5149d280],4096),
                       ('program',(out/'program.bin').read_bytes(),8192)):
    assert len(data)<=size
    data=data.ljust(size,b'\0')
    (out/(name+'.hex')).write_text(''.join(f'{int.from_bytes(data[i:i+4],"little"):08x}\n' for i in range(0,len(data),4)))
(out/'inputs.json').write_text(json.dumps(dict(nos_sha256=sha,original_code_modified=False,
    native_routines=['515BF550','515BF474','515BF65C','515BF7D8'],
    scope='original MDI ring routines on HDL CPU; authored caller and synthetic protocol peer'),indent=2)+'\n')
