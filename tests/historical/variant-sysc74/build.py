#!/usr/bin/env python3
"""Experimental full firmware boot with cache candidate; no checkpoint reuse."""
import hashlib,json,subprocess,sys
from pathlib import Path
root=Path.cwd();out=root/'build/sim/runs/variant-sysc74-checkpoint-build';out.mkdir(parents=True,exist_ok=True)
rtl=root/'scratch/no-data-cache-probe/zap/src/rtl';board=root/'scratch/variant-sysc74';obj=root/'build/sim/obj-variant-sysc74-checkpoint-build';binary=obj/'Vngage_cpu_sim'
rom=root/'build/firmware/digest-probes/both/SYM.ROM';extension=root/'build/firmware/nem4-extension/extension.bin'
inputs=[*sorted(rtl.glob('*.sv')),*sorted(rtl.glob('*.svh')),root/'rtl/ngage_cpu.sv',root/'scratch/checkpoint-probe/ngage_cpu_sim.sv',board/'main.cpp',board/'boot_profile.cpp',board/'boot_profile.h',rom,extension,Path(__file__).resolve()]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();inputs_hash={str(p.relative_to(root)):sha(p) for p in inputs}
cmd=['docker','run','--rm','--network','none','--platform','linux/arm64','-v',str(root)+':/work','-w','/work','--entrypoint','verilator','jotego/simulator:arm64','--cc','--exe','--build','-j','4','--savable','--assert','-DNGAGE_RUNTIME_TRACE','-Wno-fatal','-Wno-lint','--x-initial','0','--x-assign','0','--top-module','ngage_cpu_sim','--Mdir',str(obj.relative_to(root)),'-I'+str(rtl.relative_to(root)),'rtl/ngage_cpu.sv','scratch/checkpoint-probe/ngage_cpu_sim.sv',*[str(p.relative_to(root)) for p in sorted(rtl.glob('*.sv'))],'/work/scratch/variant-sysc74/main.cpp','/work/scratch/variant-sysc74/boot_profile.cpp']
with (out/'build.log').open('w') as f:r=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT)
if r.returncode:raise SystemExit('Build failed; see build.log')
for cache in obj.rglob('*.gch'): cache.unlink()
if any(sha(root/p)!=h for p,h in inputs_hash.items()):raise SystemExit('Inputs changed during build')
print("GPIO checkpoint simulator built", flush=True)
