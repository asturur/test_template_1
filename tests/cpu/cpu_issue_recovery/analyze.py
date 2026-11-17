#!/usr/bin/env python3
"""Audit fixed 4D, causal 4C/4D alignment, one CPU change and corrected results."""
from setup import *
from collections import Counter,defaultdict
import re
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
read=lambda p:json.loads((ROOT/p).read_text())
C='build/sim/spmark-payload/issue-recovery-control-final'
D='build/sim/spmark-payload/issue-recovery-candidate-qualified'
OLD='build/sim/spmark-payload/issue-recovery-trace-4c-01'
c,d,o=[read(x+'/result.json') for x in [C,D,OLD]]
assert c['status']==d['status']==o['status']=='PASS'
ci=c['manifest']['source']['source_id'];di=d['manifest']['source']['source_id']
assert ci=='76d176e29ae091962ebe66efe2cf0060f0d551f844fce29c014a5fd64fe6b4bb'
assert di=='9c2f022a85f3dad30026752e4537debca035b26a832821bcef950caf6edfab1c'
assert o['manifest']['source']['source_id']=='7f3ce0f6fdba8b358a57acc36fa144177cb51fd15e0dd4a1eb216c5b3463094e'
for key in ['programs','payload_sha256','original_images','original_rom_sha256','normal_import_link','profiles','repeat','harness_sha256','image_id']:assert c['manifest'][key]==d['manifest'][key],key
assert len(c['rows'])==len(d['rows'])==4
assert c['qualification']==d['qualification'] and len(d['qualification'])==2 and all(x['wrong_output_rejected'] for x in d['qualification'])
for directory,result in [(C,c),(D,d),(OLD,o)]:
 for f,h in result['manifest']['source']['files'].items():assert sha(ROOT/directory/'source'/f)==h,f
changed=[f for f,h in c['manifest']['source']['files'].items() if d['manifest']['source']['files'][f]!=h]
assert changed==['rtl/arm/zap_writeback.sv']
assert sha(HERE/'rtl/arm/zap_writeback.sv')==d['manifest']['source']['files'][changed[0]]
for a,b in zip(c['rows'],d['rows']):
 assert a['case']==b['case'] and a['profile']==b['profile'] and a['oracle']==b['oracle'] and a['payload_windows']==b['payload_windows']
 assert a['deterministic_repeats']==b['deterministic_repeats']==2
 old,new={'transpose4':(4613,4550),'matrix4':(52714,52125)}[a['case']]
 assert all(x['cycles']==old for x in a['windows'][2:]) and all(x['cycles']==new for x in b['windows'][2:])
 for row in [a,b]:assert all(x['reads']==x['writes']==x['lines']==0 for x in row['windows'][2:])
def records(directory,case,prefix,profile='0-0'):
 return [dict(re.findall(r'(\w+)=(\w+)',l)) for l in (ROOT/directory/f'{case}-{profile}-0.log').read_text().splitlines() if l.startswith(prefix+' ')]
def category(e):
 return 'read' if e['data']=='1' and e['wr']=='0' else 'write' if e['data']=='1' else 'load' if e['oval']=='1' and e['lock']=='1' and e['ll']=='1' else 'lock' if e['oval']=='1' and e['lock']=='1' else 'empty' if e['oval']=='0' else 'other'
def intervals(es):
 out=[];start=0;occ=Counter()
 for i,e in enumerate(es):
  if e['ret']=='1':
   key=(e['rpc'],occ[e['rpc']]);occ[e['rpc']]+=1
   out.append(dict(key=key,buckets=dict(Counter(category(x) for x in es[start:i+1])),start=int(es[start]['edge']),end=int(e['edge'])))
   start=i+1
 return out
def aligned(a,b):
 aa,bb=intervals(a),intervals(b);assert [x['key'] for x in aa]==[x['key'] for x in bb]
 return [dict(key=x['key'],control=x,candidate=y,empty_delta=y['buckets'].get('empty',0)-x['buckets'].get('empty',0)) for x,y in zip(aa,bb) if y['buckets'].get('empty',0)!=x['buckets'].get('empty',0)]
old_edges=records(OLD,'transpose4','ISSUE_EDGE');control_edges=records(C,'transpose4','ISSUE_EDGE')
assert len(old_edges)==4644 and len(control_edges)==4613
loss=aligned(old_edges,control_edges)
assert Counter((e['key'][0],e['empty_delta']) for e in loss)==Counter({('000000cc',1):30,('000000cc',4):1})
assert sum(e['empty_delta'] for e in loss)==34
# Match every changed load by architectural PC and occurrence, then inspect
# the REAL CPU completion edge and its held dependent store.
ro,rc=[records(x,'transpose4','LOAD_CASE') for x in [OLD,C]]
assert len(ro)==len(rc)==416
occ=Counter();changed_loads=[]
completion_maps=[]
for es in [old_edges,control_edges]:
 count=Counter();entries={}
 for e in es:
  if e['comp']=='1' and e['p2']=='1':
   key=(e['p2pc'],count[e['p2pc']]);count[e['p2pc']]+=1;entries[key]=e
 completion_maps.append(entries)
for a,b in zip(ro,rc):
 assert (a['pc'],a['addr'])==(b['pc'],b['addr'])
 key=(a['pc'],occ[a['pc']]);occ[a['pc']]+=1
 if a['latency']!=b['latency']:
  assert a['latency']=='1' and b['latency']=='0'
  edges=[m[key] for m in completion_maps]
  for e in edges:
   assert e['oval']=='1' and e['pop']=='1' and e['ll']=='0' and int(e['opc'],16)==int(a['pc'],16)+4
   assert e['ostore']=='1' and e['source3']=='3' and int(e['source0'],16)==0
   assert int(e['source1'],16)>>32==1 and int(e['source2'],16)>>32==1
  changed_loads.append(dict(key=key,address=a['addr'],control=a,candidate=b,control_completion=edges[0],candidate_completion=edges[1]))
assert Counter(x['key'][0] for x in changed_loads)==Counter({'10002648':32,'10002698':32,'10002658':1})
assert not [e for e in control_edges if e['data']=='1' and e['oval']=='0' and e['dec']=='1']
empty_dec=[e for e in control_edges if e['data']=='0' and e['oval']=='0' and e['dec']=='1']
assert len(empty_dec)==97 and all(e['push']=='1' and e['full']=='0' and e['stall']=='0' and e['clralu']==e['clrwb']==e['clrdec']=='0' for e in empty_dec)
locks=[e for e in control_edges if e['data']=='0' and e['oval']=='1' and e['ll']=='1']
store_locks=Counter(e['opc'] for e in locks if e['ostore']=='1')
assert len(locks)==863 and sum(store_locks.values())==768 and set(store_locks.values())=={128} and len(store_locks)==6
profiles=[]
for profile in ['0-0','2-9']:
 ce,de=[records(x,'transpose4','ISSUE_EDGE',profile) for x in [C,D]]
 assert len(ce)==4613 and len(de)==4550
 improvements=aligned(ce,de)
 assert Counter((x['key'][0],x['empty_delta']) for x in improvements)==Counter({('10002644',-1):31,('000000cc',-1):31,('000000d8',-1):1})
 # Second original function return: same old wrong-path fetch, same saved target.
 trace=[]
 for directory,es in [(C,ce),(D,de)]:
  revents=records(directory,'transpose4','REDIRECT_EDGE',profile)
  starts=[int(e['edge']) for i,e in enumerate(es) if e['clralu']=='1' and es[i-1]['clralu']=='0' and e['apc']=='100026a4']
  assert len(starts)==32
  begin,end=starts[1:3]
  release=next(e for e in revents if begin<=int(e['edge'])<end and e['shelve']=='1' and e['code']=='0' and e['saved']=='000000cc')
  at=int(release['edge']);strobe=next(e for e in es if int(e['edge'])>=at and e['ireq']=='1' and e['iaddr']=='000000cc')
  issue=next(e for e in es if int(e['edge'])>=at and e['pop']=='1' and e['opc']=='000000cc')
  trace.append(dict(release=release,target_strobe=strobe,first_issue=issue,strobe_delta=int(strobe['edge'])-at,issue_delta=int(issue['edge'])-at,edges=[e for e in es if at<=int(e['edge'])<=int(issue['edge'])]))
 assert [x['strobe_delta'] for x in trace]==[4,3] and [x['issue_delta'] for x in trace]==[16,15]
 profiles.append(dict(profile=profile,architectural_empty_clock_improvements=improvements,before_after_trace=trace))
def handoffs(directory,case):
 es=records(directory,case,'REDIRECT_EDGE')
 h=[e for e in es if e['shelve']=='1' and e['code']=='0' and e['wclr']=='0' and (e['aclr']=='1' and e['saved']==e['atarget'] or e['aclr']=='0' and e['dclr']=='1' and e['saved']==e['dtarget'] or e['aclr']=='0' and e['dclr']=='0')]
 return dict(count=len(h),by_target=dict(Counter(e['saved'] for e in h)),ended_strobe=sum(e['aclr']==e['dclr']=='0' for e in h),repeated_strobe=sum(e['aclr']=='1' or e['dclr']=='1' for e in h))
coverage={case:dict(control=handoffs(C,case),candidate=handoffs(D,case),control_profile=records(C,case,'CREDIT_WORK_PROFILE')[2],candidate_profile=records(D,case,'CREDIT_WORK_PROFILE')[2]) for case in ['transpose4','matrix4']}
assert coverage['transpose4']['candidate']['count']==64 and coverage['matrix4']['candidate']['count']==433
store=read('build/sim/cpu-issue-recovery/store-corrected-final/result.json');safety=read('build/sim/cpu-issue-recovery/safety-corrected-final/result.json')
for r in [store,safety]:assert r['status']=='PASS' and r['source']['source_id']==di and any('physical_writes=448 completions=448 retired=448 independent_backing_words=16' in x for x in r['events'])
assert all('issue_through_drain=71 ' in x for x in store['events'] if x.startswith('OVERLAP_SUMMARY') and 'window=0 ' not in x)
assert any(x.startswith('PASS LOAD_SAFETY') for x in safety['events'])
negative=read('build/sim/cpu-issue-recovery/store-corrected-final/wrong-physical-byte.json');assert negative['status']=='EXPECTED_FAILURE'
unit=read('build/sim/cpu-issue-recovery/redirect-corrected-final/result.json');assert unit['status']=='PASS' and 'PASS redirect_handoff checks=17' in unit['events']
unit_key='build/sim/cpu-issue-recovery/redirect-corrected-final/source/zap_writeback.sv';assert unit['source'][unit_key]==sha(HERE/'rtl/arm/zap_writeback.sv')
failed=ROOT/'build/sim/cpu-issue-recovery/redirect-fcse-carry-trace/run-0.log';corrected=ROOT/'build/sim/cpu-issue-recovery/redirect-corrected-final/run-0.log'
assert 'next=02000000 expected_next=0c000000' in failed.read_text() and 'next=0c000000 expected_next=0c000000' in corrected.read_text()
diagnostics=read('build/sim/cpu-issue-recovery/diagnostics-corrected-final/result.json')
assert diagnostics['status']=='PASS' and diagnostics['source_id']==di and len(diagnostics['rows'])==8
for r in diagnostics['rows']:
 if r['name'].startswith('btb_return'):assert r['status']=='unmapped_access' and r['blocked_address']==0x0bad0000
 else:assert r['status']=='pass'
 if r['name'].startswith('prefetch_fault'):assert r['fetch_bus_faults']>0
partial=read('build/sim/spmark-payload/issue-recovery-candidate-01/result.json');assert partial['status']=='PASS'
result=dict(decision='Retain corrected isolated CPU handoff: both original kernels improve; no fit or production adoption.',fixed_4D_source_id=ci,candidate_source_id=di,changed_files=changed,overlay_sha256={str(f.relative_to(ROOT)):sha(f) for f in (HERE/'rtl').rglob('*.sv')},helper_sha256={str(f.relative_to(ROOT)):sha(f) for f in HERE.iterdir() if f.suffix in ['.py','.v','.vh']},workloads=[dict(control=a,candidate=b) for a,b in zip(c['rows'],d['rows'])],old_4C_to_4D_accounting=dict(trace=OLD,aligned_retirements=1025,extra_empty_clocks=34,extra_empty_by_architectural_interval=loss,changed_loads=changed_loads,decoded_held_behind_empty_during_data_stall=0,normal_R_capture_empty_clocks=97,load_lock_clocks=863,store_data_only_lock_clocks=768,store_lock_by_pc=dict(store_locks)),profiles=profiles,coverage=coverage,first_partial_handoff=dict(source_id=partial['manifest']['source']['source_id'],cycles=[dict(case=r['case'],profile=r['profile'],cycles=r['body_cycles_median']) for r in partial['rows']],reason='Only repeated CPU strobes were handled; ordinary pending release after the strobe ended was initially omitted.'),fcse_failure=dict(status='FAIL_CORRECTED',failing_source=read('build/sim/cpu-issue-recovery/redirect-fcse-carry-trace/source.json'),failing_log=str(failed.relative_to(ROOT)),failing_log_sha256=sha(failed),corrected_log=str(corrected.relative_to(ROOT)),corrected_log_sha256=sha(corrected),failure_edge='raw01fffffc -> mapped0bfffffc -> next02000000; expected0c000000',correction='Advance mapped, aligned target, preserving fixed-control carry behavior.'),unit=unit,store=store,safety=safety,wrong_physical_byte=negative,diagnostics=diagnostics,raw_outputs=[C,D,OLD,'build/sim/cpu-issue-recovery'])
out=ROOT/'docs/evidence/cpu-issue-recovery-20261116.json';out.write_text(json.dumps(result,indent=2)+'\n')
print('PASS fixed4D / one-file corrected CPU handoff; exact 65-load/34-clock causal accounting; original transpose+matrix, traces, 17 edge cases, 8 real-CPU diagnostics and 71-cycle store stream:',out)
