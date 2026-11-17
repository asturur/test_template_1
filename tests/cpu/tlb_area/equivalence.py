#!/usr/bin/env python3
"""Original architectural table vs eight-comparator bank, poisoned mixed reads."""
import argparse,subprocess,json,hashlib
from pathlib import Path
from setup import ROOT,HERE,BASE
p=argparse.ArgumentParser();p.add_argument('--name',required=True);a=p.parse_args();out=ROOT/'build/sim/tlb-area'/a.name;out.mkdir(parents=True,exist_ok=False)
reference=subprocess.check_output(['git','show',BASE+':rtl/arm920/tlb_bank.sv'],cwd=ROOT).decode().replace('module arm920_tlb_bank','module reference_bank',1);(out/'reference.sv').write_text(reference)
files=[ROOT/'tests/cpu/cache_probe_retime/rtl/ngage_bram.v',HERE/'rtl/tlb_bank.sv',out/'reference.sv',HERE/'equivalence.sv']
cp=lambda p:'/work/'+str(p.relative_to(ROOT));docker=['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',str(ROOT)+':/work','-w','/work','--entrypoint']
def call(cmd,name,bad=False):
    with (out/name).open('w') as f:r=subprocess.run(cmd,cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
    if not bad:assert r.returncode==0,str(out/name)
    return r.returncode
build=docker+['verilator','jotego/simulator:arm64','--binary','--timing','--assert','-j','1','-Wno-fatal','-Wno-lint','--top-module','test','--Mdir',cp(out/'obj')]
call(build+[cp(f) for f in files],'build.log')
rows=[]
for n in range(2):
    call(docker+[cp(out/'obj/Vtest'),'jotego/simulator:arm64'],f'run-{n}.log');rows.append([l for l in (out/f'run-{n}.log').read_text().splitlines() if l.startswith(('PASS bank','AREA_EQ_LATENCY','AREA_MUTATION_DRAIN'))])
assert rows[0]==rows[1] and rows[0]
# Real negative: truncate search after the first row; late architectural slots
# must fail the unchanged oracle rather than being silently reduced to 8 entries.
mutant=(HERE/'rtl/tlb_bank.sv').read_text().replace('if(|lane_hits || row==7)','if(|lane_hits || row==0)',1);assert mutant!=(HERE/'rtl/tlb_bank.sv').read_text();(out/'truncated.sv').write_text(mutant)
call([*build[:-1],cp(out/'obj-negative'),cp(files[0]),cp(out/'truncated.sv'),cp(files[2]),cp(files[3])],'negative-build.log')
rc=call(docker+[cp(out/'obj-negative/Vtest'),'jotego/simulator:arm64'],'negative.log',True)
assert rc!=0 and 'bank equivalence address=' in (out/'negative.log').read_text()
(out/'result.json').write_text(json.dumps(dict(status='PASS',events=rows[0],truncated_capacity_rejected=True,inputs={str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in files},executable_sha256=hashlib.sha256((out/'obj/Vtest').read_bytes()).hexdigest()),indent=2)+'\n')
print(*rows[0],'PASS 8-entry truncation negative rejected',sep='\n')
