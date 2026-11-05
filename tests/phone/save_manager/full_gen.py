import importlib.util
from pathlib import Path
s=importlib.util.spec_from_file_location('save','tools/prepare_mister_save.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
core=bytes.fromhex('be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524')
ext=bytes.fromhex('cb6e0b39c90df00864fc21ee527624372b1e4f5c3ff3c985f397172d30446cf3')
h=m.make_header(1,core,ext)
Path('build/sim/unit-save-manager').mkdir(parents=True,exist_ok=True)
Path('build/sim/unit-save-manager/full_header.hex').write_text(''.join(f'{int.from_bytes(h[i:i+2],"little"):04x}\n' for i in range(0,512,2)))
