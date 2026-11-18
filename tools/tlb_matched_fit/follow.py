#!/usr/bin/env python3
"""Follow the authorized serial pair, never redispatch a recorded build."""
import datetime,json,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/fit/tlb-matched-20261117';REPO='asturur/test_template_1'
def call(args):return subprocess.check_output(args,cwd=ROOT,text=True)
def run(args):subprocess.run(args,cwd=ROOT,check=True)
def find(sha):
    runs=json.loads(call(['gh','run','list','--repo',REPO,'--workflow','ci_build.yml','--limit','20','--json','databaseId,headSha,status']))
    matches=[r for r in runs if r['headSha']==sha];assert len(matches)<=1,matches
    return matches[0]['databaseId'] if matches else None
for variant in ['5l','banked']:
    out=OUT/variant
    if not (out/'dispatched.json').exists():
        assert variant=='banked' and (OUT/'5l/verified-fit.json').exists()
        assert not (out/'publication.json').exists(),'Partial publication: inspect before retry'
        run(['python3','tools/tlb_matched_fit/prepare.py','banked'])
        with (out/'replay.log').open('w') as log:subprocess.run(['patches/zap/verify.sh'],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
        run(['python3','tools/tlb_matched_fit/publish.py','banked'])
    sha=json.loads((out/'publication.json').read_text())['sha'];rid=None
    for _ in range(20):
        rid=find(sha)
        if rid:break
        time.sleep(15)
    assert rid,'Dispatched run not yet found; inspect without redispatch'
    (out/'run-id.json').write_text(json.dumps(dict(run=rid,sha=sha))+'\n')
    last=None
    for _ in range(480):
        state=json.loads(call(['gh','run','view',str(rid),'--repo',REPO,'--json','status,conclusion,headSha,jobs']))
        assert state['headSha']==sha
        active=[s['name'] for j in state['jobs'] for s in j['steps'] if s['status']=='in_progress']
        label=(state['status'],state['conclusion'],active)
        if label!=last:
            print(datetime.datetime.now(datetime.timezone.utc).isoformat(),variant,rid,label,flush=True);last=label
        if state['status']=='completed':break
        time.sleep(45)
    assert state['status']=='completed','Timed out following; do not redispatch'
    run(['python3','tools/tlb_matched_fit/collect.py',variant,str(rid)])
run(['python3','tools/tlb_matched_fit/compare.py'])
print('BOTH FITS COLLECTED AND COMPARED',flush=True)
