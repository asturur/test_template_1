#!/usr/bin/env python3
"""Continue the preserved boot checkpoint with one more explicit write."""
import hashlib,json,subprocess,sys
from pathlib import Path
root=Path.cwd();base=root/'build/sim/runs';cp=root/'build/sim/checkpoints/ngage-before-cbus27';old=base/'boot-checkpoint-gpio206-extra';initial=base/'boot-checkpoint-initial';d=base/'boot-variant-table-trace';d.mkdir(parents=True,exist_ok=True)
manifest=json.loads((cp.parent/'ngage-before-cbus27.json').read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for ext,h in manifest['checkpoint']['files'].items():
 if sha(Path(str(cp)+ext))!=h:raise SystemExit('checkpoint hash mismatch')
for path,h in manifest['files'].items():
 if path.startswith(('scratch/no-data-cache-probe/zap/','rtl/ngage_cpu.sv','build/firmware/')) and sha(root/path)!=h:raise SystemExit(f'checkpoint input or RTL changed: {path}')
cv=lambda p:'/work/'+str(p.relative_to(root)); binary=root/'build/sim/obj-variant-table-checkpoint-build/Vngage_cpu_sim';s=root/'scratch/variant-table-trace';rtl=root/'scratch/no-data-cache-probe/zap/src/rtl';files=[binary,s/'main.cpp',s/'boot_profile.cpp',s/'boot_profile.h',s/'resume.py',*sorted(rtl.glob('*.sv')),*sorted(rtl.glob('*.svh'))]
scenario={'source_checkpoint':str(cp),'checkpoint_sha256':manifest['checkpoint']['files'],'files':{str(p.relative_to(root)):sha(p) for p in files},'extra_cbus_write':0x27,'allow_uif_halfword_write_0x0c150012':0x8000,'allow_icu25_write':0x02000000,'gpio210_low_reset_assumed':0,'gpio21a_reset_assumed':0,'gpio216_reset_assumed':0,'gpio214_low_reset_assumed':0,'pupf006_reset_assumed':0,'pupf004_low_reset_assumed':0,'gpio206_extra_write_sink':6,'uif102_write_assumed':0x10,'extra_cbus_write2':0x82,'cbus82_readback_assumed':True,'cbus80_input_assumed':0x400,'cbus8d_reset_zero_assumed':True,'icu46_write_assumed':0x4000,'pupf00a_reset_assumed':0,'sysc0c14_reset_assumed':0,'explicit_register_probes':[{'address':0x0c120c10,'initial':0,'select':15,'verified':False},{'address':0x0c120c0c,'initial':0,'select':15,'verified':False},{'address':0x0c14f000,'initial':0,'select':3,'verified':False}],'gpio206_exact_write_sink':0x0180,'caveat':'Write sink only, peripheral function and side effects unknown; D-cache forced off.'}
(d/'provenance.json').write_text(json.dumps(scenario,indent=2)+'\n');(d/'result.json').write_text('')
cmd=['docker','run','--rm','--network','none','--platform','linux/arm64','-v',str(root)+':/work','-w','/work','--entrypoint',cv(binary),'jotego/simulator:arm64',cv(root/'build/firmware/digest-probes/both/SYM.ROM'),'1000000000','0',*[cv(d/f) for f in ('instructions.tsv','bus.tsv','cp15.tsv','result.json')],'amd16','ideal-clocks','lcd-probe','boot-io-probe','+ngage-compact-trace','rom-extension='+cv(root/'build/firmware/nem4-extension/extension.bin'),'uem-adc=6=512','timer-irq-delay=18200000','uem-power-status=0','uem-status36=0','uem-status35=16','restore='+cv(cp),'cbus-write-allow=0x27','cbus-write-allow2=0x82','cbus82-readback','cbus80-input=0x400','cbus8d-zero','icu46-write','pupf00a-zero','sysc0c14-zero','probe-register=0x0c120c10:0:15','probe-register=0x0c120c0c:0:15','probe-register=0x0c14f000:0:3','probe-register=0x0c14f004:0:12','probe-register=0x0c150204:0:12','uif-write-8000','icu-write-25','gpio210-low-zero','gpio21a-zero','gpio216-zero','gpio214-low-zero','pupf004-low-zero','gpio206-extra-write','uif102-write']
with (d/'simulator.log').open('w') as f:r=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT)
if not (d/'result.json').stat().st_size:raise SystemExit(f'No result; exit {r.returncode}; inspect simulator.log')
x=json.loads((d/'result.json').read_text());print('RESULT',x['status'],x['cycles'],hex(x['blocked_address']),x.get('blocked_reason',''),flush=True)
def rows(path):
 with path.open() as f:
  next(f)
  for line in f:yield line.split('\t')
for i,(a,b) in enumerate(zip(rows(old/'bus.tsv'),rows(d/'bus.tsv'))):
 if a[1].startswith('UNMODELED'):break
 if a!=b:raise SystemExit(f'Checkpoint continuation diverged before UIF write at row {i}')
else:raise SystemExit('Previous UIF frontier not encountered during prefix comparison')
print('Verified exact bus prefix through previous PUP read/write',flush=True)
print("Resumed bus segment retained; earlier white screen remains available in the prior capture.",flush=True)
