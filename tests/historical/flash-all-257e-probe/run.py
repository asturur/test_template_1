#!/usr/bin/env python3
"""Experimental full firmware boot with cache candidate; no checkpoint reuse."""
import hashlib,json,subprocess,sys
from pathlib import Path
root=Path.cwd();out=root/'build/sim/runs/flash-all-257e-probe';out.mkdir(parents=True,exist_ok=True)
rtl=root/'rtl/arm';board=root/'scratch/flash-all-257e-probe';obj=root/'build/sim/obj-flash-all-257e-probe';binary=obj/'Vngage_cpu_sim'
rom=root/'build/firmware/digest-probes/both/SYM.ROM';extension=root/'build/firmware/nem4-extension/extension.bin'
inputs=[*sorted(rtl.glob('*.sv')),*sorted(rtl.glob('*.svh')),root/'rtl/ngage_cpu.sv',root/'scratch/checkpoint-probe/ngage_cpu_sim.sv',board/'main.cpp',board/'boot_profile.cpp',board/'boot_profile.h',rom,extension,Path(__file__).resolve()]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();inputs_hash={str(p.relative_to(root)):sha(p) for p in inputs}
cmd=['docker','run','--rm','--network','none','--platform','linux/arm64','-v',str(root)+':/work','-w','/work','--entrypoint','verilator','jotego/simulator:arm64','--cc','--exe','--build','-j','4','--savable','--assert','-DNGAGE_RUNTIME_TRACE','-Wno-fatal','-Wno-lint','--x-initial','0','--x-assign','0','--top-module','ngage_cpu_sim','--Mdir',str(obj.relative_to(root)),'-I'+str(rtl.relative_to(root)),'rtl/ngage_cpu.sv','scratch/checkpoint-probe/ngage_cpu_sim.sv',*[str(p.relative_to(root)) for p in sorted(rtl.glob('*.sv'))],'/work/scratch/flash-all-257e-probe/main.cpp','/work/scratch/flash-all-257e-probe/boot_profile.cpp']
with (out/'build.log').open('w') as f:r=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT)
if r.returncode:raise SystemExit('Build failed; see build.log')
for cache in obj.rglob('*.gch'): cache.unlink()
if any(sha(root/p)!=h for p,h in inputs_hash.items()):raise SystemExit('Inputs changed during build')
cv=lambda p:'/work/'+str(p.relative_to(root));scenario={'warning':'EXPERIMENTAL identity-v15 cache-enabled RTL and provisional devices, NOT validated hardware or authentic firmware','source_hashes':inputs_hash,'binary_sha256':sha(binary),'max_cycles':100000,'memory_latency':0,'checkpoint_restored':False,'cache_forced_off':False,'assumptions':['derived firmware digest','synthetic ROM extension','ideal clocks','LCD transport','timer IRQ delay 18200000','UEM ADC6=512','UEM power/status','CBUS write/read assumptions','GPIO and system-control probes','counterfactual all three flash IDs 0001/257e/2502/2500, handshake 0x42','GPIO206 exact writes 0x180/0x6 without side effects','GPIO214 low reset assumed zero','PUP F004 low and F006 high reset assumed zero']}
(out/'provenance.json').write_text(json.dumps(scenario,indent=2)+'\n');(out/'result.json').write_text('')
cmd=['docker','run','--rm','--network','none','--platform','linux/arm64','-v',str(root)+':/work','-w','/work','--entrypoint',cv(binary),'jotego/simulator:arm64',cv(rom),'100000','0',*[cv(out/f) for f in ('instructions.tsv','bus.tsv','cp15.tsv','result.json')],'amd16','ideal-clocks','lcd-probe','boot-io-probe','+ngage-compact-trace','rom-extension='+cv(extension),'uem-adc=6=512','timer-irq-delay=18200000','uem-power-status=0','uem-status36=0','uem-status35=16','cbus-write-allow=0x27','cbus-write-allow2=0x82','cbus82-readback','cbus80-input=0x400','cbus8d-zero','icu46-write','pupf00a-zero','sysc0c14-zero','probe-register=0x0c120c10:0:15','probe-register=0x0c120c0c:0:15','probe-register=0x0c14f000:0:3','probe-register=0x0c14f004:0:12','probe-register=0x0c150204:0:12','uif-write-8000','icu-write-25','gpio210-low-zero','gpio21a-zero','gpio216-zero','gpio214-low-zero','pupf004-low-zero','gpio206-extra-write','uif102-write']
print('Experimental cache-enabled firmware run started',flush=True)
# Drain all simulator output, while capping disk usage and counting omitted bytes.
with (out/'simulator.log').open('wb') as f:
 p=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 saved=omitted=0
 while True:
  chunk=p.stdout.read(65536)
  if not chunk: break
  keep=min(len(chunk),max(0,1048576-saved))
  if keep: f.write(chunk[:keep]);saved+=keep
  omitted+=len(chunk)-keep
 rc=p.wait()
 f.write(f'\n[Log limited to 1048576 bytes; omitted {omitted} bytes.]\n'.encode())
class Result: pass
r=Result();r.returncode=rc

if not (out/'result.json').stat().st_size:raise SystemExit(f'No result, simulator exit {r.returncode}; inspect simulator.log')
if any(sha(root/p)!=h for p,h in inputs_hash.items()) or sha(binary)!=scenario['binary_sha256']:raise SystemExit('Inputs changed while simulation ran; do not use result')
x=json.loads((out/'result.json').read_text());print('RESULT',x['status'],x['cycles'],hex(x['blocked_address']),x.get('blocked_reason',''),flush=True)
print('Short flash-ID diagnostic; no LCD capture.',flush=True)
