#!/usr/bin/env python3
"""Authentic-path full firmware boot from reset: V15 cache CPU, all-0x257e flash,
periodic tick hypothesis, no RAM intervention. Builds first when needed."""
import hashlib,json,subprocess,sys
from pathlib import Path
root=Path.cwd();out=root/'build/sim/runs/boot-v15-nosprobe';out.mkdir(parents=True,exist_ok=True)
rtl=root/'rtl/arm';board=root/'scratch/boot-v15-nosprobe';obj=root/'build/sim/obj-boot-v15-nosprobe';binary=obj/'Vngage_cpu_sim'
rom=root/'build/firmware/nem4-factory/digest-probe-core/SYM.ROM';extension=root/'build/firmware/nem4-factory/extension.bin'
inputs=[*sorted(rtl.glob('*.sv')),*sorted(rtl.glob('*.svh')),root/'rtl/ngage_cpu.sv',root/'scratch/checkpoint-probe/ngage_cpu_sim.sv',board/'main.cpp',board/'boot_profile.cpp',board/'boot_profile.h',rom,extension,Path(__file__).resolve()]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();inputs_hash={str(p.relative_to(root)):sha(p) for p in inputs}
if not binary.exists():raise SystemExit('Build first: python3 scratch/boot-v15-periodic/build.py')
cv=lambda p:'/work/'+str(p.relative_to(root))
scenario={'warning':'EXPERIMENTAL identity-v15 cache-enabled RTL and provisional devices, NOT validated hardware; authentic-path configuration (no RAM intervention, no checkpoint)','source_hashes':inputs_hash,'binary_sha256':sha(binary),'max_cycles':1000000000,'memory_latency':0,'checkpoint_restored':False,'cache_forced_off':False,'assumptions':['derived firmware digest (16/31 metadata bytes)','synthetic ROM extension','ideal clocks','LCD transport hypothesis','boot one-shot timer reload 0x0115b5c0 modeled as 18200000-cycle delay','periodic tick: kernel reload 0x632ea with control 2 arms free-running IrqTimer0, ICU current reads 1, any 0x0c120a08 write acknowledges, stale early enable cleared at kernel reload; verified against kernel disassembly 0x5032287c/0x503225b0; tick unit one CPU cycle unverified','all three flash chips 0x0001/0x257e/0x2502/0x2500 handshake 0x0042 (Nokia-custom AM29N643 hypothesis; unique self-consistent configuration per probe/classifier/validator disassembly)','UEM ADC6=512','UEM power/status assumptions','CBUS write/read assumptions','GPIO/PUP/system-control reset-value probes','FIQ enable-set 0x0c1201c8 exact sink; no FIQ source modeled','block 0x0c14d000-10 and 0x0c150538/53c zero-reset probe (function unverified)','debug character-output sink at physical 0x0de00000/0x0dfd0000 (write-only, bytes retained)','kernel-phase UEM register reads 0x24/0x31 answered with constant 0 (hypotheses)']}
(out/'provenance.json').write_text(json.dumps(scenario,indent=2)+'\n');(out/'result.json').write_text('')
cmd=['docker','run','--rm','--network','none','--platform','linux/arm64','-v',str(root)+':/work','-w','/work','--entrypoint',cv(binary),'jotego/simulator:arm64',cv(rom),'1000000000','0',*[cv(out/f) for f in ('instructions.tsv','bus.tsv','cp15.tsv','result.json')],'amd16','ideal-clocks','lcd-probe','boot-io-probe','+ngage-compact-trace','rom-extension='+cv(extension),'uem-adc=6=512','timer-irq-delay=18200000','uem-power-status=0','uem-status36=0','uem-status35=16','cbus-write-allow=0x27','cbus-write-allow2=0x82','cbus82-readback','cbus80-input=0x400','cbus8d-zero','icu46-write','pupf00a-zero','sysc0c14-zero','probe-register=0x0c120c10:0:15','probe-register=0x0c120c0c:0:15','probe-register=0x0c14f000:0:3','probe-register=0x0c14f004:0:12','probe-register=0x0c150204:0:12','uif-write-8000','icu-write-25','gpio210-low-zero','gpio21a-zero','gpio216-zero','gpio214-low-zero','pupf004-low-zero','gpio206-extra-write','sysc74-write3','gpio24-28-write1','timer-compare-probe','sysc50-44-probe','icu1c8-probe','timer-periodic','block14d-probe','debug59-sink','cbus-input=0x20=0','cbus-input=0x21=0','cbus-input=0x22=0','cbus-input=0x23=0','cbus-input=0x24=0','cbus-input=0x25=0','cbus-input=0x26=0','cbus-input=0x27=0','cbus-input=0x28=0','cbus-input=0x29=0','cbus-input=0x2a=0','cbus-input=0x2b=0','cbus-input=0x2c=0','cbus-input=0x2d=0','cbus-input=0x2e=0','cbus-input=0x2f=0','cbus-input=0x30=0','cbus-input=0x31=0','cbus-input=0x32=0','cbus-input=0x33=0','cbus-input=0x34=0','uif102-write']
print('Authentic-path V15 firmware run started',flush=True)
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
if not (out/'result.json').stat().st_size:raise SystemExit(f'No result, simulator exit {rc}; inspect simulator.log')
if any(sha(root/p)!=h for p,h in inputs_hash.items()) or sha(binary)!=scenario['binary_sha256']:raise SystemExit('Inputs changed while simulation ran; do not use result')
x=json.loads((out/'result.json').read_text());print('RESULT',x['status'],x['cycles'],hex(x['blocked_address']),x.get('blocked_reason',''),flush=True)
screen=root/'build/sim/screens/boot-v15-nosprobe'
capture=subprocess.run([sys.executable,'sim/capture_lcd_screen.py',str(out/'bus.tsv'),'--output',str(screen)],capture_output=True,text=True)
print((capture.stdout if capture.returncode==0 else 'SCREEN NOT CAPTURED: '+capture.stderr).strip(),flush=True)
