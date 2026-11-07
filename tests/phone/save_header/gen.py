import importlib.util
from pathlib import Path
spec=importlib.util.spec_from_file_location('save','tools/prepare_mister_save.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
a=bytes(range(32));b=bytes(range(32,64));h=m.make_header(1,a,b)
Path('build/sim/unit-save-header').mkdir(parents=True,exist_ok=True)
Path('build/sim/unit-save-header/header.hex').write_text(''.join(f'{int.from_bytes(h[i:i+2],"little"):04x}\n' for i in range(0,len(h),2)))

for profile in (2,3):
 h=m.make_header(profile,a,b)
 Path(f'build/sim/unit-save-header/header{profile}.hex').write_text(''.join(f'{int.from_bytes(h[i:i+2],"little"):04x}\n' for i in range(0,len(h),2)))
