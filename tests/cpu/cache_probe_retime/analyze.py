#!/usr/bin/env python3
"""Validate the matched CPU comparisons and collect compact offline evidence."""
from pathlib import Path
import json,re,hashlib,math,statistics
ROOT=Path(__file__).resolve().parents[3]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
load=lambda p:json.loads(p.read_text())
rows=[];runs={};indexes={}
for kind in ['spmark-payload','jpeg-payload']:
 base=ROOT/'build/sim'/kind
 dirs={v:base/f'probe-retime-{v}-20261116' for v in ['control','candidate']}
 result={v:load(d/'result.json') for v,d in dirs.items()}
 assert all(j['status']=='PASS' for j in result.values())
 manifests={v:j['manifest'] for v,j in result.items()}
 fields=['programs','image_id','harness_sha256','payload_sha256']
 fields+=['original_rom_sha256','profiles','repeat'] if kind=='spmark-payload' else ['rom_sha256','observer_sha256']
 for field in fields:assert manifests['control'][field]==manifests['candidate'][field],(kind,field)
 for variant,d in dirs.items():
  selected=ROOT/'tests/cpu/cache_probe_retime/rtl' if variant=='candidate' else ROOT/'tests/cpu/cache_resident_qualification/rtl'
  for n in ['cache_access.sv','cache_bank.sv','cache_tags.sv','cache_adapter.sv']:
   original=selected/n if (selected/n).exists() else ROOT/'rtl/arm920'/n
   assert manifests[variant]['source']['files']['rtl/arm920/'+n]==sha(original),(kind,variant,n)
  assert manifests[variant]['source']['files']['rtl/ngage_bram.v']==sha(ROOT/'rtl/ngage_bram.v')
  files=manifests[variant]['source']['files']
  for p,h in files.items():assert sha(d/'source'/p)==h,(variant,p)
  runs[f'{kind}/{variant}']={'directory':str(d.relative_to(ROOT)),'manifest_sha256':sha(d/'manifest.json'),'result_sha256':sha(d/'result.json'),'source_id':manifests[variant]['source']['source_id']}
 def key(row):return row['case'],row['profile'] if kind=='spmark-payload' else row['memory_profile']
 before={key(r):r for r in result['control']['rows']};after={key(r):r for r in result['candidate']['rows']};assert before.keys()==after.keys()
 for (case,profile),b in before.items():
  c=after[case,profile];bo=b if kind=='spmark-payload' else b['observation'];co=c if kind=='spmark-payload' else c['observation']
  assert b['oracle']==c['oracle']
  iw,dw=profile.split(':')
  metrics={}
  for variant,d in dirs.items():
   def parse(rep):
    txt=(d/f'{case}-{iw}-{dw}-{rep}.log').read_text()
    return [{k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',l)} for l in txt.splitlines() if l.startswith('PROBE_METRIC ')]
   m=parse(0);assert len(m)==7 and m==parse(1)
   obs=bo if variant=='control' else co
   assert [v['cycles'] for v in m]==[w['cycles'] for w in obs['windows']]
   metrics[variant]=m
  a,bcy=bo['body_cycles_median'],co['body_cycles_median']
  row={'kind':kind,'case':case,'profile':profile,'control_cycles':a,'candidate_cycles':bcy,'delta_cycles':bcy-a,'delta_percent':100*(bcy/a-1),'metrics_window3':{v:m[3] for v,m in metrics.items()},'metric_delta_window3':{k:metrics['candidate'][3][k]-metrics['control'][3][k] for k in metrics['control'][3] if k!='index'}}
  if kind=='jpeg-payload':
   row['wait_state_delta_window3']={k:c['profile']['windows'][3]['cache_states'][k]-n for k,n in b['profile']['windows'][3]['cache_states'].items()}
  rows.append(row)
 for variant,d in dirs.items():
  if kind=='spmark-payload':assert len(result[variant]['qualification'])==6 and all(r['wrong_output_rejected'] for r in result[variant]['qualification'])
  else:
   for case in set(r['case'] for r in result[variant]['rows']):assert 'guest result check failed' in (d/(case+'-wrong-output.log')).read_text()
 for p in ['0:0','2:9']:
  rr=[r for r in rows if r['kind']==kind and r['profile']==p]
  indexes[f'{kind}/{p}']=100*math.exp(statistics.mean(math.log(r['control_cycles']/r['candidate_cycles']) for r in rr))
unitdirs={
 'adapter':'probe-retime-adapter-20261116-01','admit':'probe-retime-admit-20261116-01','qualification':'probe-retime-qualification-20261116-01',
 'adapter_lock':'probe-retime-adapter-lock-20261116-01','refill':'probe-retime-refill-20261116-01','maintenance':'probe-retime-maintenance-20261116-01',
 'schedule_control':'probe-retime-schedule-control-20261116-02','schedule':'probe-retime-schedule-20261116-02','negative':'probe-retime-token-negative-20261116-02',
 'stream_default':'probe-retime-stream-default-20261116-01','stream_integrated':'probe-retime-stream-integrated-20261116-01'}
units={}
for name,dirname in unitdirs.items():
 d=ROOT/'build/sim'/dirname;j=load(d/'result.json');units[name]={'directory':str(d.relative_to(ROOT)),'manifest_sha256':sha(d/'source.json'),'result_sha256':sha(d/'result.json')}
 if name.startswith('stream'):
  for r in j['streams']:assert r['accepted']==r['committed']==r['responses']==256 and r['accept_intervals']==r['commit_intervals']=={'1':255}
  units[name]['streams']=j['streams'];units[name]['repeat']=j['repeat'];units[name]['negative_control']=j['negative_control']
 else:
  text=(d/'run.log').read_text()
  if name=='negative':assert j['exit_code']!=0 and 'retimed result token identity mismatch against physical RAM read slot' in text
  else:assert j['exit_code']==0 and 'PASS' in text
  units[name]['pass_lines']=[s for s in text.splitlines() if s.startswith('PASS')]
  units[name]['run_log_sha256']=sha(d/'run.log')
  if name in ['schedule','schedule_control']:
   units[name]['edge_sample']=[s for s in text.splitlines() if s.startswith('SCHEDULE') and 'phase=1 ' in s][:9]
   units[name]['case_lines']=[s for s in text.splitlines() if s.startswith('CASE')]
   grouped={}
   for line in text.splitlines():
    if not line.startswith('SCHEDULE'):continue
    fields={k:int(v) for k,v in re.findall(r'(e|phase|event|stage)=(\d+)',line)}
    key=f"phase{fields['phase']}/event{fields['event']}/stage{fields['stage']}"
    grouped.setdefault(key,[]).append(line)
   units[name]['stage_edge_samples']={k:v if len(v)<=8 else v[:4]+v[-4:] for k,v in grouped.items()}
  if name=='negative':units[name]['failure_trace']=text.splitlines()[:6]
rtl=ROOT/'tests/cpu/cache_probe_retime/rtl'
hashes={str(p.relative_to(ROOT)):sha(p) for p in sorted(rtl.glob('*'))}
# The qualified dirty forwarding and actual RAM implementation are unchanged.
for n in ['cache_bank.sv','cache_tags.sv','ngage_bram.v']:assert (rtl/n).read_bytes()==(ROOT/'tests/cpu/cache_resident_qualification/rtl'/n).read_bytes()
assert len(rows)==20 and max(r['delta_percent'] for r in rows)<2
result={'decision':'YES: this exact overlay merits a matched seed-42 measurement fit; no CI submitted or timing claim. Store-owner/certificate paths remain separate open timing work.',
 'base':'9c948da8da413a882e0fe8e559c380ea0cadabf4','rtl_sha256':hashes,'CPU_comparisons':rows,'throughput_indexes_control_100':indexes,'CPU_runs':runs,'units':units,
 'remaining_3B_paths_ns':{'certificate_to_store_owner_104_hot':-1.168,'reset_drain_to_store_payload_104_hot':-2.283},'new_routed_slack':'UNMEASURED'}
(ROOT/'docs/evidence/cache-probe-admission-retime-20261116.json').write_text(json.dumps(result,indent=2)+'\n')
print('PASS: 20 matched CPU groups, identical guest images/harness/oracles, exact repeats, all bad-output controls and unit/store gates')
print('Maximum cycle regression',max(r['delta_percent'] for r in rows));print(indexes)
