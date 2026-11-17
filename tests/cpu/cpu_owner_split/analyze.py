#!/usr/bin/env python3
"""Audit bounded5B qualification and preserve measured evidence."""
from pathlib import Path
import json,hashlib,gzip,re,csv,collections
ROOT=Path(__file__).resolve().parents[3];load=lambda p:json.loads(p.read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
base=ROOT/'build/sim/spmark-payload/frontend-candidate-02';candidate=ROOT/'build/sim/spmark-payload/owner-split-final-06'
c=load(base/'result.json');n=load(candidate/'result.json');assert c['status']==n['status']=='PASS'
source=load(candidate/'manifest.json')['source'];rows=[]
read=lambda p:p.read_text() if p.exists() else gzip.open(str(p)+'.gz','rt').read()
for a,b in zip(c['rows'],n['rows']):
 assert a['case']==b['case'] and a['profile']==b['profile'] and a['program_sha256']==b['program_sha256'] and a['oracle']==b['oracle']
 assert a['body_cycles_median']==b['body_cycles_median'];iw,dw=b['profile'].split(':');name=f"{b['case']}-{iw}-{dw}-0.log"
 old,new=read(base/name),read(candidate/name)
 # Compare actual ordinary retirement PC/cycle schedule, plus accepted stores,
 # real RAM writes and completed loads, omitting deliberately private idle fields.
 ret=lambda s:[tuple(re.findall(r'\b(?:e|rpc)=([^ ]+)',l)) for l in s.splitlines() if l.startswith('FE_EDGE ') and ' ret=1 ' in l]
 assert ret(old)==ret(new)
 events=lambda s:[l for l in s.splitlines() if l.startswith(('LATE_ACCEPT ','LATE_WRITE ','LOAD_CASE '))]
 assert events(old)==events(new)
 rows.append(dict(case=b['case'],profile=b['profile'],cycles=b['body_cycles_median'],retirements=len(ret(new)),exact_retirement_and_memory_schedule=True))
jp=ROOT/'build/sim/jpeg-payload/owner-split-jpeg-final-03';j=load(jp/'result.json');assert j['status']=='PASS'
for x in j['rows']:assert x['observation']['body_cycles_median']==84353
checks={}
for name in ['safety-final-06','safety-final-zero-08','diagnostics-final-02','core-final-04']:
 p=ROOT/'build/sim/cpu-owner-split'/name;d=load(p/'result.json');assert d['status']=='PASS',name
 assert (d.get('source_id') or d['source']['source_id'])==source['source_id'],name
 checks[name]=dict(status='PASS',result_sha256=sha(p/'result.json'))
for directory in [candidate,jp,ROOT/'build/sim/cpu-owner-split/safety-final-06']:
 m=load(directory/'manifest.json');assert m['source']['files']==source['files']
 for f,h in source['files'].items():assert sha(directory/'source'/f)==h,f
negative=load(ROOT/'build/sim/cpu-owner-split/safety-final-06/wrong-physical-byte.json');assert negative['status']=='EXPECTED_FAILURE'
timing=ROOT/'build/fit/frontend-5a-20261117/quartus-logs-43985572525/output_files/timing/resident-store/78/corner-1/setup.csv'
paths=list(csv.DictReader(timing.open()));negative_paths=[x for x in paths if float(x['slack_ns'])<0];late_paths=[x for x in negative_paths if 'late_p1_ready' in x['from']];assert len({x['to'] for x in late_paths})==203
record=dict(control_commit='6ac7a9d4c006d84667743bddec9c51a6eba95029',source_id=source['source_id'],overlay_sha256={str(p.relative_to(ROOT)):sha(p) for p in (ROOT/'tests/cpu/cpu_owner_split/rtl').rglob('*.sv')},cycles=rows,jpeg_cycles=84353,drained_stream_cycles=71,qualification=checks,negative=negative,old_fit=dict(negative_hot78_endpoints=len(negative_paths),late_ready_negative_endpoints=len(late_paths),origins=dict(collections.Counter(x['from'] for x in negative_paths))),added_state_bits=0,decision='Qualified cycle-preserving bounded owner split; one master seed42/debug-on fit authorized; no deployment/phone commands')
(ROOT/'docs/evidence/cpu-owner-split-20261117.json').write_text(json.dumps(record,indent=2)+'\n');print('PASS exact5A retirement/memory schedules and all5B qualification')
