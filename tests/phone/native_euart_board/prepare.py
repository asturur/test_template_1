"""Copy audited original driver/HAL/IAT bytes, with no instruction substitutions."""
from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[3]
out=root/'build/sim/unit-native-euart-board'
rom=(root/'build/firmware/nem4-factory/core.bin').read_bytes()
sha=hashlib.sha256(rom).hexdigest()
assert sha=='be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524'
ranges={'hal':(0x50324000,4096),'poll':(0x5033c000,4096),'iat':(0x50348000,4096),'driver':(0x510e8000,8192)}
for name,(address,size) in ranges.items():
 data=rom[address-0x50000000:address-0x50000000+size]
 assert len(data)==size
 (out/(name+'.hex')).write_text(''.join(f'{int.from_bytes(data[i:i+4],"little"):08x}\n' for i in range(0,size,4)))
data=(out/'program.bin').read_bytes();assert len(data)<=8192;data=data.ljust(8192,b'\0')
(out/'program.hex').write_text(''.join(f'{int.from_bytes(data[i:i+4],"little"):08x}\n' for i in range(0,len(data),4)))
(out/'inputs.json').write_text(json.dumps(dict(rom_sha256=sha,original_code_modified=False,ranges=ranges,scope='original EUART TX/RX/HAL on HDL CPU through production board/CTSI; authored FIQ wrapper and device byte loopback'),indent=2)+'\n')
