#!/usr/bin/env python3
"""Audit one early-address/late-data prototype against exact corrected 4E."""
from setup import *
from collections import Counter,defaultdict
import re
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
read=lambda p:json.loads((ROOT/p).read_text())
C='build/sim/spmark-payload/store-late-control-final';D='build/sim/spmark-payload/store-late-candidate-final'
c,d=[read(x+'/result.json') for x in [C,D]]
ci=c['manifest']['source']['source_id'];di=d['manifest']['source']['source_id']
assert ci=='9c2f022a85f3dad30026752e4537debca035b26a832821bcef950caf6edfab1c'
assert di=='0bf6550b3c7d9035f3d7c548c4731076b88ed024ed8590f1ebef0df320f1f081'
assert c['status']==d['status']=='PASS' and len(c['rows'])==len(d['rows'])==4
for key in ['programs','payload_sha256','original_images','original_rom_sha256','normal_import_link','profiles','repeat','harness_sha256','image_id']:assert c['manifest'][key]==d['manifest'][key],key
assert c['qualification']==d['qualification'] and len(d['qualification'])==2 and all(x['wrong_output_rejected'] for x in d['qualification'])
for directory,result in [(C,c),(D,d)]:
 for f,h in result['manifest']['source']['files'].items():assert sha(ROOT/directory/'source'/f)==h,f
changed=sorted(f for f,h in c['manifest']['source']['files'].items() if d['manifest']['source']['files'][f]!=h)
assert changed==['rtl/arm/'+x for x in ['zap_alu_main.sv','zap_core.sv','zap_issue_main.sv','zap_postalu_main.sv','zap_shifter_main.sv']]
for f in (HERE/'rtl').rglob('*.sv'):assert sha(f)==d['manifest']['source']['files']['rtl/'+str(f.relative_to(HERE/'rtl'))]
first=read('build/sim/spmark-payload/store-late-candidate-01/result.json');assert first['status']=='PASS' and first['manifest']['source']['source_id']==di
for a,b in zip(c['rows'],d['rows']):
 assert a['case']==b['case'] and a['profile']==b['profile'] and a['oracle']==b['oracle'] and a['payload_windows']==b['payload_windows']
 assert a['deterministic_repeats']==b['deterministic_repeats']==2
 old,new=(4550,4041) if a['case']=='transpose4' else (52125,52125)
 assert all(w['cycles']==old for w in a['windows'][2:]) and all(w['cycles']==new for w in b['windows'][2:])
 for row in [a,b]:assert all(w['reads']==w['writes']==w['lines']==0 for w in row['windows'][2:])
def rec(directory,prefix,profile='0-0',case='transpose4'):
 return [dict(re.findall(r'(\w+)=(\w+)',l)) for l in (ROOT/directory/f'{case}-{profile}-0.log').read_text().splitlines() if l.startswith(prefix+' ')]
def bucket(e):
 return 'read' if e['data']=='1' and e['wr']=='0' else 'write' if e['data']=='1' else 'load' if e['oval']=='1' and e['lock']=='1' and e['ll']=='1' else 'lock' if e['oval']=='1' and e['lock']=='1' else 'empty' if e['oval']=='0' else 'other'
def intervals(es):
 out=[];start=0;occ=Counter()
 for i,e in enumerate(es):
  if e['ret']=='1':
   key=(e['rpc'],occ[e['rpc']]);occ[e['rpc']]+=1
   out.append(dict(key=key,buckets=dict(Counter(bucket(x) for x in es[start:i+1])),start=int(es[start]['edge']),end=int(e['edge'])));start=i+1
 return out
store_pcs=['1000264c','1000265c','1000266c','1000267c','1000268c','1000269c']
profiles=[]
for profile in ['0-0','2-9']:
 es,ns=[rec(x,'ISSUE_EDGE',profile) for x in [C,D]]
 assert len(es)==4550 and len(ns)==4041
 ints,nints=intervals(es),intervals(ns);assert len(ints)==len(nints)==1025 and [x['key'] for x in ints]==[x['key'] for x in nints]
 empty_changes=[dict(key=a['key'],delta=b['buckets'].get('empty',0)-a['buckets'].get('empty',0)) for a,b in zip(ints,nints) if a['buckets'].get('empty',0)!=b['buckets'].get('empty',0)]
 assert sum(x['delta'] for x in empty_changes)==-125
 assert Counter((x['key'][0],x['delta']) for x in empty_changes)==Counter({('10002698',1):32,('1000269c',-3):32,('100026a0',2):32,('000000cc',-4):31,('000000cc',-1):1})
 accepts,writes=[rec(C,x,profile) for x in ['LATE_ACCEPT','LATE_WRITE']]
 naccepts,nwrites=[rec(D,x,profile) for x in ['LATE_ACCEPT','LATE_WRITE']]
 assert len(accepts)==len(writes)==len(naccepts)==len(nwrites)==384
 for lists in [(accepts,writes),(naccepts,nwrites),(accepts,naccepts),(writes,nwrites)]:
  assert [(x['pc'],x['addr'],x['data']) for x in lists[0]]==[(x['pc'],x['addr'],x['data']) for x in lists[1]]
 for a,w in zip(naccepts,nwrites):assert int(w['edge'])-int(a['edge'])==2
 early,private,data=[rec(D,x,profile) for x in ['LATE_EARLY_ISSUE','LATE_PRIVATE_ADDRESS','LATE_DATA']]
 assert len(early)==len(private)==len(data)==192
 for e,p,v in zip(early,private,data):
  assert e['pc']==p['pc']==v['pc'] and int(e['producer'],16)+4==int(e['pc'],16) and v['producer']==e['producer'] and e['rd']==v['rd']=='3'
  assert int(e['edge'])<int(p['edge'])<int(v['edge']) and v['source']=='P2_registered'
 assert rec(D,'LATE_OWNERS',profile)==[dict(issued='192',address='192',exact_data='192',accepted='192')]
 def sequence(edges,aa,ww):
  comp=defaultdict(list);issue=defaultdict(list);al=defaultdict(list);ac=defaultdict(list);wr=defaultdict(list)
  for e in edges:
   if e['comp']=='1' and e['p2']=='1':comp[e['p2pc']].append(int(e['edge']))
   if e['pop']=='1':issue[e['opc']].append(int(e['edge']))
   if e['alu']=='1' and e['apc'] in store_pcs:al[e['apc']].append(int(e['edge']))
  for e in aa:ac[e['pc']].append(e)
  for e in ww:wr[e['pc']].append(e)
  return comp,issue,al,ac,wr
 cc,ii,al,ac,wc=sequence(es,accepts,writes);nc,ni,nal,nac,nwc=sequence(ns,naccepts,nwrites)
 entries=[]
 for pc in store_pcs:
  for occurrence,a in enumerate(ac[pc]):
   second=f'{int(pc,16)+4:08x}';nextpc=f'{int(pc,16)+8:08x}';producer=f'{int(pc,16)-4:08x}'
   t=cc[producer][occurrence];nt=nc[producer][occurrence]
   before=dict(producer_completion=t,issue=ii[pc][occurrence],address_registered=al[pc][occurrence],accept=int(a['edge']),write=int(wc[pc][occurrence]['edge']),second_accept=int(ac[second][occurrence]['edge']),second_write=int(wc[second][occurrence]['edge']),next_issue=ii[nextpc][occurrence])
   owner_index=next(j for j,x in enumerate(early) if x['pc']==pc and sum(y['pc']==pc for y in early[:j])==occurrence)
   e,p,v=early[owner_index],private[owner_index],data[owner_index]
   after=dict(producer_completion=nt,issue=int(e['edge']),address_registered=int(p['edge']),accept=int(nac[pc][occurrence]['edge']),write=int(nwc[pc][occurrence]['edge']),second_accept=int(nac[second][occurrence]['edge']),second_write=int(nwc[second][occurrence]['edge']),next_issue=ni[nextpc][occurrence])
   assert [before[x]-t for x in ['issue','address_registered','accept','write','second_accept','second_write','next_issue']]==[0,3,5,7,6,8,2]
   assert [after[x]-nt for x in ['accept','write','second_accept','second_write','next_issue']]==[0,2,4,6,0]
   assert int(v['edge'])==nt and v['value']==nac[pc][occurrence]['data'] and p['addr']==nac[pc][occurrence]['addr']
   entries.append(dict(store_pc=pc,occurrence=occurrence,address=a['addr'],data=a['data'],before=before,after=after))
 # Every return arrives to an already completed wrong-path fetch in 4F;
 # the control usually has five more clocks of draining before redirect.
 return_traces=[]
 for edges in [es,ns]:
  starts=[i for i,e in enumerate(edges) if e['clralu']=='1' and edges[i-1]['clralu']=='0' and e['apc']=='100026a4'];assert len(starts)==32
  summaries=[]
  for i in starts:
   e=edges[i];target=next(x for x in edges[i:] if x['ireq']=='1' and x['iaddr']=='000000cc');pop=next(x for x in edges[i:] if x['pop']=='1' and x['opc']=='000000cc')
   summaries.append(dict(clear=e,target=target,issue=pop,target_delta=int(target['edge'])-int(e['edge']),issue_delta=int(pop['edge'])-int(e['edge'])))
  return_traces.append(summaries)
 assert Counter(x['issue_delta'] for x in return_traces[0])==Counter({20:31,17:1}) and Counter(x['issue_delta'] for x in return_traces[1])==Counter({16:32})
 cp=rec(C,'CREDIT_WORK_PROFILE',profile)[2];np=rec(D,'CREDIT_WORK_PROFILE',profile)[2]
 assert [cp[x] for x in ['read_stall','write_stall','load_lock','other_lock','empty','other']]==['737','192','863','64','1607','1087']
 assert [np[x] for x in ['read_stall','write_stall','load_lock','other_lock','empty','other']]==['737','192','479','64','1482','1087']
 oldlocks=Counter(e['opc'] for e in es if e['data']=='0' and e['oval']=='1' and e['ll']=='1')
 newlocks=Counter(e['opc'] for e in ns if e['data']=='0' and e['oval']=='1' and e['ll']=='1')
 assert all(oldlocks[pc]==128 and newlocks[pc]==0 and newlocks[f'{int(pc,16)+4:08x}']==64 for pc in store_pcs)
 profiles.append(dict(profile=profile,records=entries,physical_writes=384,owned_early_stores=192,private_address_lead_histogram=dict(Counter(str(int(v['edge'])-int(p['edge'])) for p,v in zip(private,data))),control_profile=cp,candidate_profile=np,control_locks=dict(oldlocks),candidate_locks=dict(newlocks),empty_clock_changes=empty_changes,return_traces=return_traces))
# Matrix has no eligible class: preserve its original work and full counters.
assert rec(D,'LATE_OWNERS',case='matrix4')==[dict(issued='0',address='0',exact_data='0',accepted='0')]
assert rec(C,'CREDIT_WORK_PROFILE',case='matrix4')==rec(D,'CREDIT_WORK_PROFILE',case='matrix4')
store_c=read('build/sim/cpu-store-late/store-control-01/result.json');store_d=read('build/sim/cpu-store-late/store-candidate-01/result.json')
for r,identity in [(store_c,ci),(store_d,di)]:
 assert r['status']=='PASS' and r['source']['source_id']==identity
 assert all('issue_through_drain=71 ' in x for x in r['events'] if x.startswith('OVERLAP_SUMMARY') and 'window=0 ' not in x)
 assert any('physical_writes=448 completions=448 retired=448 independent_backing_words=16' in x for x in r['events'])
assert store_c['events']==store_d['events']
smc,smd=[read('build/sim/cpu-store-late/'+x+'/manifest.json') for x in ['store-control-01','store-candidate-01']];assert smc['program_sha256']==smd['program_sha256']
store_profiles=[]
for profile,names in [('0:0',['store-control-01','store-candidate-01']),('2:9',['store-control-2-9','store-candidate-2-9'])]:
 results=[read('build/sim/cpu-store-late/'+name+'/result.json') for name in names]
 manifests=[read('build/sim/cpu-store-late/'+name+'/manifest.json') for name in names]
 for name,r,m,identity in zip(names,results,manifests,[ci,di]):
  assert r['status']=='PASS' and r['source']['source_id']==m['source']['source_id']==identity
  assert m['program_sha256']==smc['program_sha256']
  assert all('issue_through_drain=71 ' in x for x in r['events'] if x.startswith('OVERLAP_SUMMARY') and 'window=0 ' not in x)
  assert any('physical_writes=448 completions=448 retired=448 independent_backing_words=16' in x for x in r['events'])
  def stream_events(repeat):
   return [x for x in (ROOT/'build/sim/cpu-store-late'/name/f'run-{repeat}.log').read_text().splitlines() if x in r['events']]
  assert stream_events(0)==stream_events(1)==r['events']
 assert results[0]['events']==results[1]['events']
 store_profiles.append(dict(profile=profile,outputs=names,program_sha256=smc['program_sha256'],control=results[0],candidate=results[1]))
hc,hd=[read('build/sim/cpu-store-late/'+x+'/result.json') for x in ['safety-control-01','safety-candidate-03']]
assert hc['status']==hd['status']=='PASS' and hc['source']['source_id']==ci and hd['source']['source_id']==di
hcm,hdm=[read('build/sim/cpu-store-late/'+x+'/manifest.json') for x in ['safety-control-01','safety-candidate-03']];assert hcm['program_sha256']==hdm['program_sha256']
hdir=ROOT/'build/sim/cpu-store-late/safety-candidate-03'
def hazard_records(p):return [x for x in p.read_text().splitlines() if x.startswith(('LATE_SAFETY_CASE','PASS LATE_SAFETY'))]
assert hazard_records(hdir/'run-0.log')==hazard_records(hdir/'run-1.log')
hcases=[dict((k,int(v)) for k,v in re.findall(r'(\w+)=(\d+)',line)) for line in hazard_records(hdir/'run-0.log') if line.startswith('LATE_SAFETY_CASE')]
assert len(hcases)==7
for case in hcases:
 i=case['case'];assert case['early']==(0 if i==2 else 1) and case['accepts']==(1 if i<5 else 0) and case['physical_writes']==(1 if i in [0,1,2,4] else 0)
assert hcases[1]['P2_formatted']==1 and hcases[5]['P1_data']==hcases[5]['P2_formatted']==0 and hcases[6]['P1_data']==1
assert any('held_private_address_clocks=199 exactly_once_device=1' in x for x in hazard_records(hdir/'run-0.log'))
neg=read('build/sim/cpu-store-late/store-candidate-01/wrong-physical-byte.json');assert neg['status']=='EXPECTED_FAILURE'
diag=read('build/sim/cpu-store-late/diagnostics-candidate-01/result.json');assert diag['status']=='PASS' and diag['source_id']==di and len(diag['rows'])==8
for r in diag['rows']:
 if r['name'].startswith('btb_return'):assert r['status']=='unmapped_access' and r['blocked_address']==0x0bad0000
 else:assert r['status']=='pass'
 if r['name'].startswith('prefetch_fault'):assert r['fetch_bus_faults']>0
preflight=read('build/sim/spmark-payload/store-late-control-01/preflight.json');assert len(preflight['pairs'])==192 and preflight['observed_lock_clocks']==768
result=dict(decision='Retain the correct isolated 4F candidate: transpose -509 cycles; matrix and store stream unchanged. No fit or production adoption.',fixed_4E_source_id=ci,candidate_source_id=di,changed_files=changed,logical_new_state_bits=5,new_payload_flops=0,overlay_sha256={str(f.relative_to(ROOT)):sha(f) for f in (HERE/'rtl').rglob('*.sv')},helper_sha256={str(f.relative_to(ROOT)):sha(f) for f in HERE.iterdir() if f.suffix in ['.py','.v','.vh']},workloads=[dict(control=a,candidate=b) for a,b in zip(c['rows'],d['rows'])],preflight_initial_optimistic=preflight,measured_clock_accounting=dict(old_observed_locks=768,new_exposed_second_store_locks=384,net_local_clocks_saved=384,additional_return_empty_clocks_saved=125,total_clocks_saved=509,initial_optimistic_limit=576,model_correction='The unmodified second store requires five issue-to-demand clocks, so its last write moves c+8 to c+6, a two-clock local gain.'),profiles=profiles,store_control=store_c,store_candidate=store_d,safety_control=hc,safety_candidate=hd,focused_cases=hcases,focused_event_repeats=hazard_records(hdir/'run-0.log'),wrong_physical_byte=neg,diagnostics=diag,failed_fixtures=[dict(log='build/sim/cpu-store-late/safety-candidate-01/run-0.log',reason='New cache-disrupting hazard prelude needed the original two-line certificate warm-up restored before the existing physical-way oracle.'),dict(log='build/sim/cpu-store-late/safety-candidate-02/run-0.log',reason='Permission-case base still depended on a literal load; added an explicit dependency-consuming move to prepare the base and exercise early allocation.')],raw_outputs=[C,D,'build/sim/cpu-store-late'])
result['standard_store_profiles']=store_profiles
out=ROOT/'docs/evidence/cpu-store-late-20261116.json';out.write_text(json.dumps(result,indent=2)+'\n')
print('PASS exact4E / one5-bit CPU prototype; 192 owned address/data transfers,384 actual writes; transpose4041/matrix52125/stores71; fault/permission/format/MMIO/base hazards and8 diagnostics:',out)
