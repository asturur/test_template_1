"""Prepare immutable original NEM-4 code for the CPU/CBUS fixture."""
import hashlib
import json
from pathlib import Path
root=Path(__file__).resolve().parents[3]
out=root/'build/sim/unit-native-cbus'
rom=(root/'build/firmware/nem4-factory/core.bin').read_bytes()
sha=hashlib.sha256(rom).hexdigest()
if sha!='be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524':
    raise ValueError('requires audited original NEM-4 service backing')
for name,data,size in (('original',rom[0x300000:0x400000],0x100000),
                       ('program',(out/'program.bin').read_bytes(),8192)):
    if len(data)>size:raise ValueError('fixture bounds')
    data=data.ljust(size,b'\0')
    (out/(name+'.hex')).write_text(''.join(f'{int.from_bytes(data[i:i+4],"little"):08x}\n' for i in range(0,len(data),4)))
(out/'inputs.json').write_text(json.dumps(dict(original_sha256=sha,original_code_modified=False,
    boundary='native HAL virtual peripheral alias to CBUS physical bus; no MMU qualification'),indent=2)+'\n')
