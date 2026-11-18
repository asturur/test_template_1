#!/usr/bin/env python3
"""Compare completed runs with their actual predecessor up to its unknown access."""
import json
from pathlib import Path
root=Path(__file__).resolve().parents[2];r=root/'build/sim/runs'
pairs=[('boot-checkpoint-pupf000','boot-checkpoint-gpio214','bus-segment.tsv'),('boot-checkpoint-gpio214','boot-checkpoint-pupf006','bus.tsv'),('boot-checkpoint-pupf006','boot-checkpoint-pupf004','bus.tsv'),('boot-checkpoint-pupf004','boot-checkpoint-gpio206-extra','bus.tsv'),('boot-checkpoint-pupf004','boot-variant-counterfactual','bus.tsv'),('boot-variant-counterfactual','boot-variant-sysc74','bus.tsv'),('boot-variant-sysc74','boot-variant-gpio24','bus.tsv'),('boot-variant-gpio24','boot-variant-timercompare','bus.tsv'),('boot-variant-timercompare','boot-variant-sysc50','bus.tsv'),('boot-variant-sysc50','boot-variant-icu1c8','bus.tsv')]
results=[]
for old,new,filename in pairs:
 a=(r/old/filename).read_text().splitlines()[1:];b=(r/new/'bus.tsv').read_text().splitlines()[1:]
 for i,(x,y) in enumerate(zip(a,b)):
  if '\tUNMODELED_' in x:break
  if x!=y:raise SystemExit(f'prefix mismatch {old} -> {new}, row {i}: {x} vs {y}')
 else:raise SystemExit(f'frontier missing {old} -> {new}')
 results.append({'previous':old,'current':new,'matching_rows':i,'frontier':a[i]})
(r/'boot-variant-icu1c8/prefix-audit.json').write_text(json.dumps(results,indent=2)+'\n')
print('PASS',len(results),'predecessor comparisons')
