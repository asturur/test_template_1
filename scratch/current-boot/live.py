#!/usr/bin/env python3
"""Run current CPU firmware simulation and save each completed LCD update."""
import os, struct, subprocess, sys, time
from pathlib import Path
root=Path(__file__).resolve().parents[2]
os.chdir(root)
sys.path.insert(0,str(root/'scratch/tools'))
from lcd_live import LCD
from direct_lcd import DirectLCD
name=sys.argv[1] if len(sys.argv)>1 else 'current-c11-20b'
if not name or any(c not in 'abcdefghijklmnopqrstuvwxyz0123456789-' for c in name): raise SystemExit('Use lowercase letters, digits and hyphens for run name')
run=root/'build/sim/runs'/('boot-v15-'+name)
screen=root/'build/sim/screens'/('boot-v15-'+name+'-live')
if run.exists() or screen.exists() or list((root/'build/sim/checkpoints').glob('roll-'+name+'-r*')):
 raise SystemExit('Run name already exists; choose a new name as an argument.')
screen.mkdir(parents=True)
args=[sys.executable,'scratch/current-boot/run.py',os.environ.get('NGAGE_SIM_CYCLES','20000000000'),name,'','0','unused','cdrive-image=/work/scratch/overnight/cdrive-11b.img','pmm-image=/work/scratch/overnight/pmm-aan.bin','cbus-input=0x24=1','uem-power-status-extra=2']
if os.environ.get('NGAGE_CHECKPOINT_EVERY'): args.append('checkpoint-every='+os.environ['NGAGE_CHECKPOINT_EVERY'])
print('Screens:',screen,flush=True)
print('Starting from cycle 0 with the current CPU and 11B C: image; checkpoint every billion.',flush=True)
p=subprocess.Popen(args)
path=run/'live-lcd.bin'; offset=0; bus_offset=0; lcd=LCD(screen); direct=DirectLCD(lcd)
try:
 while True:
  bus=run/'bus.tsv'
  if bus.exists():
   with bus.open('r') as f:
    f.seek(bus_offset)
    while True:
     start=f.tell();line=f.readline()
     if not line or not line.endswith('\n'):
      f.seek(start);break
     bus_offset=f.tell()
     frame=direct.feed(line)
     if frame:print('LCD direct frame (RGB444 assumption):',frame.name,flush=True)
  if path.exists():
   with path.open('rb') as f:
    f.seek(offset)
    while True:
     start=f.tell();head=f.read(16)
     if len(head)<16:break
     cycle,src,count=struct.unpack('<QII',head)
     if count>0x40000: raise RuntimeError('invalid LCD record')
     data=f.read(count*4)
     if len(data)<count*4:break
     offset=f.tell()
     frame=lcd.apply(cycle,src,data)
     if frame:print('LCD update:',frame.name,flush=True)
     else:print('LCD update incomplete or outside known screen, cycle',cycle,flush=True)
  if p.poll() is not None:
   print('Simulation exited:',p.returncode,flush=True);sys.exit(p.returncode)
  time.sleep(1)
except KeyboardInterrupt:
 p.terminate();p.wait();raise
