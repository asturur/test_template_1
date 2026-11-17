#!/usr/bin/env python3
"""Record broad 5L results separately before stacking any admission experiment."""
import hashlib,json,math,re,gzip
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
load=lambda p:json.loads((ROOT/p).read_text())
new=load('build/sim/spmark-payload/step5l-six-01/result.json');old=load('build/sim/spmark-payload/combined-5jk-release-01/result.json');reused=load('docs/evidence/cpu-late-operand-20261117.json')
assert new['status']==old['status']==reused['status']=='PASS'
nm=new['manifest'];om=old['manifest']
for k in ['programs','payload_sha256','original_images','original_rom_sha256','harness_sha256','image_id','profiles','repeat']:assert nm[k]==om[k],k
rtl={k:v for k,v in nm['source']['files'].items() if k.startswith('rtl/') and Path(k).suffix in ['.v','.sv','.svh']}
assert len(rtl)==60 and all(reused['candidate_manifest']['source']['files'][k]==v for k,v in rtl.items())
assert len(new['rows'])==12 and len(new['qualification'])==6
rows=[]
for n in new['rows']:
    b=next(x for x in old['rows'] if (x['case'],x['profile'])==(n['case'],n['profile']))
    assert n['oracle']==b['oracle'] and n['deterministic_repeats']==2
    rows.append(dict(case=n['case'],profile=n['profile'],control=b['body_cycles_median'],late=n['body_cycles_median'],saved=b['body_cycles_median']-n['body_cycles_median']))
index={p:math.prod(x['control']/x['late'] for x in rows if x['profile']==p)**(1/6) for p in nm['profiles']}
out=ROOT/'build/sim/spmark-payload/step5l-six-01';dat=out/'obj/Vbench__verFiles.dat';receipt=out/'compiler-inputs.json'
if dat.exists():
    names=set(re.findall(r'^S[^\n]*"/work/[^"\n]*/source/(rtl/[^"\n]+)"',dat.read_text(),re.M));receipt.write_text(json.dumps({n:rtl[n] for n in sorted(names)},indent=2)+'\n')
assert len(json.loads(receipt.read_text()))==51
result=dict(status='PASS',decision='Keep exact retained 5L for next isolated experiment; broad qualification has no regression',rows=rows,geometric_throughput=index,manifest=nm,qualification=new['qualification'],original_rows=new['rows'],control_manifest=om,reused_evidence_sha256=hashlib.sha256((ROOT/'docs/evidence/cpu-late-operand-20261117.json').read_bytes()).hexdigest(),reused=['original Thumb JPEG 84353 both profiles','game 34995/34920','single/multiline streams 343/499','precise flags, predicated writer, IRQ, fault, missing response and retry controls'],compiler_inputs=json.loads(receipt.read_text()))
(ROOT/'docs/evidence/cpu-late-operand-six-20261117.json').write_text(json.dumps(result,indent=2)+'\n')
print('PASS six original kernels, exact 5L hashes, original outputs/retirements/repeats/negatives; geomean',index)
