"""Shared explicit, hash-qualified final 4C closure for the isolated 4D runners."""
from pathlib import Path
import hashlib,json,shutil
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
def verify_controls():
 for topic in ['cache-probe-admission-retime','cpu-store-overlap','cpu-load-delivery']:
  evidence=json.loads((ROOT/'docs/evidence'/(topic+'-20261116.json')).read_text())
  for name,value in evidence.get('rtl_sha256',evidence.get('overlay_sha256',{})).items():
   assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==value,name
 evidence=json.loads((ROOT/'docs/evidence/cpu-store-credit-20261116.json').read_text())
 assert hashlib.sha256((ROOT/'tests/cpu/cpu_store_credit/rtl/arm920/cache_adapter.sv').read_bytes()).hexdigest()==evidence['candidate_adapter_sha256']
verify_controls()
LAYERS=['cache_probe_retime','cpu_store_overlap','cpu_store_credit','cpu_load_delivery']
def overlay(destination,candidate):
 for layer in LAYERS:
  base=ROOT/'tests/cpu'/layer/'rtl'
  for f in base.rglob('*.sv'):
   relative=f.relative_to(base)
   if layer=='cache_probe_retime':relative=Path('arm920')/f.name
   shutil.copyfile(f,destination/'rtl'/relative)
 if candidate:
  for f in (HERE/'rtl').rglob('*.sv'):shutil.copyfile(f,destination/'rtl'/f.relative_to(HERE/'rtl'))
