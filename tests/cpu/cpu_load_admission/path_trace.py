#!/usr/bin/env python3
"""Extract the exact routed 5K motivation before selecting the 5M boundary."""
import json,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
p=ROOT/'build/fit/combined-5jk-20261117/summary.json';summary=json.loads(p.read_text())
def find(v):
    if isinstance(v,str) and 'Data Arrival Path' in v and '13.073' in v:return v
    for x in v.values() if isinstance(v,dict) else v if isinstance(v,list) else []:
        r=find(x)
        if r:return r
text=find(summary);assert text
part=text.split('Data Arrival Path',1)[1].split('Data Required Path',1)[0]
rows=[]
for line in part.splitlines():
    fields=[x.strip() for x in line.split(';')[1:-1]]
    if len(fields)==7 and fields[3] in ['CELL','IC','uTco']:rows.append(dict(zip(['total_ns','increment_ns','edge','type','fanout','location','element'],fields)))
receipt=dict(control_commit='ccba54f60a2c6f4741e74428b3306a19717ea58d',fit_run='44123116917',summary_sha256=hashlib.sha256(p.read_bytes()).hexdigest(),global_worst_path=summary['global_worst_path'],arrival_rows=rows,interpretation='Logical CP15 table-base context -> TLB owner/busy -> resident fast_hit -> request_ack -> completion capture/retimed late_p1_ready register. Original RTL completion is registered; physical endpoint is Quartus-created. Current permission will be registered with request ownership before ACK selection; revocation must use a registered context-change event, not live wide context comparison.')
target=ROOT/'docs/evidence/cpu-load-admission-path-20261117.json';target.write_text(json.dumps(receipt,indent=2)+'\n')
print('Recorded exact 5K routed launch/capture path before 5M implementation')
if __name__=='__main__':pass
