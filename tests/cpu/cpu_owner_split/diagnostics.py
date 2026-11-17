#!/usr/bin/env python3
"""Focused real-CPU redirect/fetch-fault/FCSE checks on an accepted frozen source."""
from setup import *
import argparse,subprocess,importlib.util,sys
p=argparse.ArgumentParser();p.add_argument('name');p.add_argument('--build',type=Path,required=True);a=p.parse_args()
out=ROOT/'build/sim/cpu-owner-split'/a.name;out.mkdir(parents=True,exist_ok=False)
(out/'result.json').write_text('{"status":"INCOMPLETE"}\n')
build=ROOT/a.build;manifest=json.loads((build/'manifest.json').read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for f,h in manifest['source']['files'].items():assert sha(build/'source'/f)==h
source=out/'source';shutil.copytree(build/'source',source)
sys.path.insert(0,str(ROOT/'sim'))
spec=importlib.util.spec_from_file_location('isolated_diagnostics',ROOT/'sim/run.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
m.BUILD=out
old_docker=m.docker
def docker(command,extra_mounts=()):
 args=old_docker(command,extra_mounts);args.insert(3,'--pull=never');return args
m.docker=docker
rtl=[source/'rtl/ngage_cpu.sv',source/'rtl/ngage_bram.v']
for directory in ['arm','arm920']:rtl+=sorted((source/'rtl'/directory).glob('*.sv'))
inputs=rtl+sorted((source/'rtl/arm').glob('*.svh'))+[ROOT/'sim'/f for f in ['ngage_cpu_sim.sv','main.cpp','boot_profile.cpp','boot_profile.h']]
obj=out/'obj';exe=obj/'Vngage_cpu_sim'
cmd=['verilator','--cc','--exe','--build','-j','4','--assert','-DNGAGE_RUNTIME_TRACE','-Wno-fatal','-Wno-lint','--x-initial','0','--x-assign','0','--top-module','ngage_cpu_sim','--Mdir',str(obj.relative_to(ROOT)),'-I'+str((source/'rtl/arm').relative_to(ROOT)),*[str(f.relative_to(ROOT)) for f in rtl],'sim/ngage_cpu_sim.sv','/work/sim/main.cpp','/work/sim/boot_profile.cpp']
m.execute(docker(cmd),out/'build.log')
binary_manifest=dict(source_id=manifest['source']['source_id'],binary_sha256=sha(exe),inputs={str(f.relative_to(ROOT)):sha(f) for f in inputs})
(obj/'ngage-build-manifest.json').write_text(json.dumps(binary_manifest,indent=2)+'\n')
rows=[]
for case in ['smoke','mmu_fcse','prefetch_fault','btb_return']:
 rom=m.assemble(case)
 for latency in [0,3]:
  options=dict(boot_profile='amd16',boot_io_probe=True,expected_status='unmapped_access') if case=='btb_return' else {}
  r=m.run_case(exe,case+'-latency'+str(latency),rom,latency=latency,**options)
  if case=='btb_return':assert r['blocked_address']==0x0bad0000
  else:assert r['status']=='pass'
  if case=='prefetch_fault':assert r['fetch_bus_faults']>0
  rows.append(r)
assert all(sha(ROOT/f)==h for f,h in binary_manifest['inputs'].items())
(out/'result.json').write_text(json.dumps(dict(status='PASS',source_id=manifest['source']['source_id'],rows=rows),indent=2)+'\n')
print('PASS focused real-CPU ARM/Thumb, FCSE, discarded/actual prefetch abort and BTB-alias return:',out/'result.json')
