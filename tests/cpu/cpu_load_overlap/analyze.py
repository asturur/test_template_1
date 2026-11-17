#!/usr/bin/env python3
"""Audit measured 4D identities, per-owner gains and correctness; save evidence."""
from setup import *
from collections import Counter,defaultdict
import re,subprocess
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
read=lambda p:json.loads((ROOT/p).read_text())
C='build/sim/spmark-payload/load-overlap-control-final'
D='build/sim/spmark-payload/load-overlap-candidate-measured'
c,d=read(C+'/result.json'),read(D+'/result.json')
assert c['status']==d['status']=='PASS'
ci=c['manifest']['source']['source_id'];di=d['manifest']['source']['source_id']
assert ci=='7f3ce0f6fdba8b358a57acc36fa144177cb51fd15e0dd4a1eb216c5b3463094e'
assert di=='76d176e29ae091962ebe66efe2cf0060f0d551f844fce29c014a5fd64fe6b4bb'
for key in ['programs','payload_sha256','original_images','original_rom_sha256','normal_import_link','profiles','repeat','harness_sha256','image_id']:assert c['manifest'][key]==d['manifest'][key],key
assert len(c['rows'])==len(d['rows'])==2
assert c['qualification']==d['qualification'] and all(x['wrong_output_rejected'] for x in d['qualification'])
for a,b in zip(c['rows'],d['rows']):
 assert a['profile']==b['profile'] and a['oracle']==b['oracle'] and a['payload_windows']==b['payload_windows']
 assert a['deterministic_repeats']==b['deterministic_repeats']==2
 assert all(x['cycles']==4644 for x in a['windows'][2:]) and all(x['cycles']==4613 for x in b['windows'][2:])
 for row in [a,b]:assert all(x['reads']==x['writes']==x['lines']==0 for x in row['windows'][2:])
for directory,result in [(C,c),(D,d)]:
 for f,h in result['manifest']['source']['files'].items():assert sha(ROOT/directory/'source'/f)==h,f
changed=sorted(f for f in c['manifest']['source']['files'] if c['manifest']['source']['files'][f]!=d['manifest']['source']['files'][f])
assert len(changed)==12
for f in (HERE/'rtl').rglob('*.sv'):assert sha(f)==d['manifest']['source']['files']['rtl/'+str(f.relative_to(HERE/'rtl'))]
def records(path,prefix):
 return [dict(re.findall(r'(\w+)=([\w:]+)',l)) for l in (ROOT/path).read_text().splitlines() if l.startswith(prefix+' ')]
per_profile=[]
for profile in ['0-0','2-9']:
 paths=[x+f'/transpose4-{profile}-0.log' for x in [C,D]]
 cr,dr=[records(x,'LOAD_CASE') for x in paths]
 assert len(cr)==len(dr)==416 and all(x['external']=='0' for x in cr+dr)
 changes=[]
 for a,b in zip(cr,dr):
  assert (a['pc'],a['addr'],a['certified'])==(b['pc'],b['addr'],b['certified'])
  if a['latency']!=b['latency']:
   assert a['latency']=='1' and b['latency']=='0'
   changes.append(dict(control=a,candidate=b))
 assert Counter(x['control']['pc'] for x in changes)==Counter({'10002648':32,'10002698':32,'10002658':1})
 edges=records(paths[0],'PAIR_EDGE');candidate_edges=records(paths[1],'PAIR_EDGE')
 groups=defaultdict(list)
 for e in edges:groups[tuple(e[k] for k in ['old_pc','next_pc','old_va','next_va'])].append(e)
 assert len(groups)==192 and all(v[0]['old_rd']!=v[0]['next_rd'] and v[0]['same_block']=='1' for v in groups.values())
 replies=[e for e in edges if e['ack']=='1' and e['complete']=='0']
 assert len(replies)==192
 assert Counter((x['state'],x['next_cert']) for x in replies)==Counter({('0','1'):96,('13','1'):34,('2','1'):31,('13','0'):31})
 newslots=[e for e in candidate_edges if e['state'] in ['2','13'] and e['probe']=='1']
 assert len(newslots)==65 and all(e['next_cert']=='1' and e['pending']=='0' and e['collision']=='0' and e['trans']=='1' and e['fault']=='0' for e in newslots)
 first=[]
 for path in paths:
  edges0=records(path,'LOAD_EDGE');start=int(edges0[0]['edge'])
  co=records(path,'PAIR_COMPLETE');reg=records(path,'PAIR_REGISTER');st=records(path,'PAIR_DEPSTORE')
  assert [(x['pc'],x['rd'],x['data']) for x in co[:2]]==[('10002644','2','a846e198'),('10002648','3','1b1ee3ff')]
  assert [(x['pc'],x['rd'],x['data']) for x in reg[:2]]==[('10002644','2','a846e198'),('10002648','3','1b1ee3ff')]
  assert [(x['pc'],x['addr'],x['data']) for x in st[:2]]==[('1000264c','80001004','1b1ee3ff'),('10002650','80001010','a846e198')]
  first.append(dict(base_edge=start,edges=edges0[:20],completions=co[:2],register_writes=reg[:2],dependent_stores=st[:2]))
 per_profile.append(dict(profile=profile,changes=changes,pairs=192,new_reply_read_slots=65,already_fast_pairs=96,uncertified_second_lines=31,paired_edges=739,translation_unavailable_edges=sum(e['trans']=='0' for e in edges),store_pending_edges=sum(e['pending']!='0' for e in edges),same_slot_collision_edges=sum(e['collision']=='1' for e in edges),pair_state_edges=dict(Counter(e['state'] for e in edges)),first_pair=first,control_metrics=records(paths[0],'CREDIT_WORK_PROFILE')[2],candidate_metrics=records(paths[1],'CREDIT_WORK_PROFILE')[2]))
loops=[]
for directory,identity,cycles in [('pairs-control-measured',ci,698),('pairs-candidate-measured',di,634)]:
 r=read('build/sim/cpu-load-overlap/'+directory+'/result.json');assert r['status']=='PASS' and r['source_id']==identity
 assert r['warmups']==3 and r['samples']==5 and r['deterministic_repeats']==2
 assert all(row['cycles']==cycles and all(w['cycles']==cycles for w in row['windows'][3:]) for row in r['rows'])
 assert r['qualification']==['wrong checksum rejected'];loops.append(r)
assert loops[0]['program_sha256']==loops[1]['program_sha256'] and loops[0]['payload_sha256']==loops[1]['payload_sha256'] and loops[0]['oracle']==loops[1]['oracle']
store=read('build/sim/cpu-load-overlap/store-stream-final/result.json');safety=read('build/sim/cpu-load-overlap/store-safety-final-03/result.json')
for r in [store,safety]:assert r['status']=='PASS' and r['source']['source_id']==di and any('physical_writes=448 completions=448 retired=448 independent_backing_words=16' in x for x in r['events'])
assert all('issue_through_drain=71 ' in e for e in store['events'] if e.startswith('OVERLAP_SUMMARY') and 'window=0 ' not in e)
assert any(x.startswith('PASS LOAD_SAFETY') for x in safety['events'])
neg=read('build/sim/cpu-load-overlap/store-stream-final/wrong-physical-byte.json');assert neg['status']=='EXPECTED_FAILURE'
pressure=read('build/sim/cpu-load-overlap/pressure-candidate-01/result.json');assert pressure['status']=='PASS'
assert len([x for x in pressure['events'] if x.startswith('PRESSURE_CASE')])==10
for f in (HERE/'rtl/arm920').glob('*.sv'):
 key='build/sim/cpu-load-overlap/pressure-candidate-01/source/'+f.name
 assert pressure['source'][key]==sha(f)
compat=[read('build/sim/'+x+'/result.json') for x in ['load-overlap-probe-final','load-overlap-admit-final']]
assert all(r['exit_code']==0 for r in compat)
result=dict(decision='Retain bounded offline improvement; no fit or production adoption authorized.',base='9c948da8da413a882e0fe8e559c380ea0cadabf4',fixed_4C_source_id=ci,candidate_source_id=di,changed_files=changed,overlay_sha256={str(f.relative_to(ROOT)):sha(f) for f in sorted((HERE/'rtl').rglob('*.sv'))},observer_sha256={str(f.relative_to(ROOT)):sha(f) for f in [HERE/'payload_tb.v',HERE/'profile.vh',HERE/'pair.vh',HERE/'tb.v',HERE/'observe.vh',HERE/'safety.vh']},workloads=[dict(control=a,candidate=b) for a,b in zip(c['rows'],d['rows'])],pair_profiles=per_profile,independent_loop=loops,store=store,safety=safety,pressure=pressure,compatibility=compat,wrong_physical_byte=neg,raw_outputs=[C,D,'build/sim/cpu-load-overlap'])
p=ROOT/'docs/evidence/cpu-load-overlap-20261116.json';p.write_text(json.dumps(result,indent=2)+'\n')
print('PASS fixed4C / final4D hashes, original oracles, 65 exact read-owner gains, 192-pair coverage, in-order data/register/store traces, pair loop, store stream, safety and pressure:',p)
