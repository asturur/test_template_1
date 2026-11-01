#!/usr/bin/env python3
"""Experimental full firmware boot with cache candidate; no checkpoint reuse."""
import hashlib,json,subprocess,sys
from pathlib import Path
root=Path.cwd();out=root/'build/sim/runs/boot-v15-nosprobe-build';out.mkdir(parents=True,exist_ok=True)
rtl=root/'rtl/arm';board=root/'scratch/boot-v15-nosprobe';obj=root/'build/sim/obj-boot-v15-nosprobe';binary=obj/'Vngage_cpu_sim'
rom=root/'build/firmware/digest-probes/both/SYM.ROM';extension=root/'build/firmware/nem4-extension/extension.bin'
inputs=[*sorted(rtl.glob('*.sv')),*sorted(rtl.glob('*.svh')),root/'rtl/ngage_cpu.sv',root/'scratch/checkpoint-probe/ngage_cpu_sim.sv',board/'main.cpp',board/'boot_profile.cpp',board/'boot_profile.h',rom,extension,Path(__file__).resolve()]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();inputs_hash={str(p.relative_to(root)):sha(p) for p in inputs}
cmd=['docker','run','--rm','--network','none','--platform','linux/arm64','-v',str(root)+':/work','-w','/work','--entrypoint','verilator','jotego/simulator:arm64','--cc','--exe','--build','-j','4','--savable','--assert','-DNGAGE_RUNTIME_TRACE','-Wno-fatal','-Wno-lint','--x-initial','0','--x-assign','0','--top-module','ngage_cpu_sim','--Mdir',str(obj.relative_to(root)),'-I'+str(rtl.relative_to(root)),'rtl/ngage_cpu.sv','scratch/checkpoint-probe/ngage_cpu_sim.sv',*[str(p.relative_to(root)) for p in sorted(rtl.glob('*.sv'))],'/work/scratch/boot-v15-nosprobe/main.cpp','/work/scratch/boot-v15-nosprobe/boot_profile.cpp','/work/scratch/modem/ngage_modem.c']
# Force recompiling the C++ harness: make's mtime check missed quick successive edits (stale binary, 2026-11-01).
for stale in ('boot_profile.o','main.o','ngage_modem.o'): (obj/stale).unlink(missing_ok=True)
with (out/'build.log').open('w') as f:r=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT)
if r.returncode:raise SystemExit('Build failed; see build.log')
for cache in obj.rglob('*.gch'): cache.unlink()
if any(sha(root/p)!=h for p,h in inputs_hash.items()):raise SystemExit('Inputs changed during build')
print("V15 periodic simulator built", flush=True)
