#!/usr/bin/env python3
"""Follow and collect the already-submitted single fit. Never dispatch a run."""
from pathlib import Path
import datetime, json, subprocess, time

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/fit/probe-retime-20261116'
REPO='asturur/test_template_1'
RUN='43906110604'
EXPECTED='418f6f824ab2e3353f71692382770433d5f0c093'
previous=None
while True:
    raw=subprocess.check_output(['gh','run','view',RUN,'--repo',REPO,'--json','headSha,headBranch,status,conclusion,url,jobs,createdAt,startedAt,updatedAt'],cwd=ROOT,text=True)
    run=json.loads(raw)
    assert run['headSha']==EXPECTED
    (OUT/'run.json').write_text(raw+'\n')
    phase=[s['name'] for j in run['jobs'] for s in j['steps'] if s['status']=='in_progress']
    current=(run['status'],run['conclusion'],tuple(phase))
    if current!=previous:
        print(datetime.datetime.now(datetime.timezone.utc).isoformat(),current,flush=True)
        previous=current
    if run['status']=='completed': break
    time.sleep(45)
with (OUT/'job.log').open('w') as log:
    subprocess.run(['gh','run','view',RUN,'--repo',REPO,'--log'],cwd=ROOT,stdout=log,check=True)
subprocess.run(['gh','run','download',RUN,'--repo',REPO,'--name','quartus-logs','--dir',str(OUT/'candidate')],cwd=ROOT,check=True)
print('Collected completed run metadata, full job log and quartus-logs artifact',flush=True)
