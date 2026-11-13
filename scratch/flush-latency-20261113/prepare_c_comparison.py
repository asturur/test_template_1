"""Build a guarded volatile C-only data comparison; never touches card files."""
import argparse,base64,hashlib,inspect,json,sys
from pathlib import Path
sys.path.insert(0,'tools')
import prepare_native_observer as native
import ngage_runtime_bt as runtime
root=Path('scratch/flush-latency-20261113')
data=Path('scratch/menu-bringup-20261112/menu-working-c.vhd').read_bytes()
assert len(data)==0x400000 and hashlib.sha256(data).hexdigest()=='4a75e4cb75d5fb25c4148f888e3e4858e37841f97834df7a002d6f38ca15b329'
s='import base64,hashlib,json,mmap,os,struct,time\n'
s+='BASE=0x30000000\n'
for f in [runtime.snapshot,native.held_fresh]:s+='\n'+inspect.getsource(f)+'\n'
s+='data=base64.b64decode('+repr(base64.b64encode(data).decode())+')\n'
s+='''
fd=os.open('/dev/mem',os.O_RDWR|os.O_SYNC)
try:
 with mmap.mmap(fd,0x1810000,access=mmap.ACCESS_WRITE,offset=BASE) as m:
  rom=hashlib.sha256(m[:0x13f0000]).hexdigest()
  assert rom=='922b6e0e23354ba63e486e501991b6aced1a4c7b71800da31842e4035e018e58'
  assert hashlib.sha256(m[0x1400000:0x1800000]).hexdigest()=='af5017dcc0d4979ae9c7313a3a77295922009f08e26fbb559bd90d9539190a47'
  pmm=hashlib.sha256(m[0x1800000:0x1810000]).hexdigest()
  assert pmm=='71189f7fb6aed638640078fba3a35fda6c39c8962e74dcc75935aac948da9063'
  a=snapshot(m);assert held_fresh(a)
  time.sleep(.2);b=snapshot(m);assert held_fresh(b) and a[2]!=b[2]
  m[0x1400000:0x1800000]=data
  assert bytes(m[0x1400000:0x1800000])==data
  assert hashlib.sha256(m[:0x13f0000]).hexdigest()==rom
  assert hashlib.sha256(m[0x1800000:0x1810000]).hexdigest()==pmm
  assert held_fresh(snapshot(m))
  print(json.dumps(dict(applied=True,c_sha256=hashlib.sha256(data).hexdigest(),rom_unchanged=rom,pmm_unchanged=pmm,card_files_unchanged=True,fresh_hold=True)))
finally:os.close(fd)
'''
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--original-rom',action='store_true')
args=parser.parse_args()
if args.original_rom:s=s.replace('922b6e0e23354ba63e486e501991b6aced1a4c7b71800da31842e4035e018e58',runtime.ROM_SHA)
(root/('apply_original_c.py' if args.original_rom else 'apply_c_comparison.py')).write_text(s)
print('Prepared C-only comparison',hashlib.sha256(data).hexdigest())
