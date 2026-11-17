#!/usr/bin/env python3
"""Audit the bounded 4G producer/data transfer and matched original workloads."""
from setup import *
from collections import defaultdict,Counter
import re
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
read=lambda p:json.loads((ROOT/p).read_text())
C='build/sim/spmark-payload/store-second-control-01';D='build/sim/spmark-payload/store-second-candidate-02'
c,d=[read(x+'/result.json') for x in [C,D]]
ci=c['manifest']['source']['source_id'];di=d['manifest']['source']['source_id']
assert ci==evidence['candidate_source_id']=='0bf6550b3c7d9035f3d7c548c4731076b88ed024ed8590f1ebef0df320f1f081'
assert di=='7b9a7dd28baccdfedfe75baaac91358c7751ed56d977fe348101738946e40244'
assert c['status']==d['status']=='PASS' and len(c['rows'])==len(d['rows'])==4
for k in ['programs','payload_sha256','original_images','original_rom_sha256','normal_import_link','profiles','repeat','harness_sha256','image_id']:assert c['manifest'][k]==d['manifest'][k],k
assert c['qualification']==d['qualification'] and all(x['wrong_output_rejected'] for x in d['qualification'])
for directory,r in [(C,c),(D,d)]:
 for f,h in r['manifest']['source']['files'].items():assert sha(ROOT/directory/'source'/f)==h
changed=sorted(f for f,h in c['manifest']['source']['files'].items() if d['manifest']['source']['files'][f]!=h)
assert changed==['rtl/arm/'+f for f in ['zap_core.sv','zap_issue_main.sv','zap_shifter_main.sv']]
for f in (HERE/'rtl').rglob('*.sv'):assert sha(f)==d['manifest']['source']['files']['rtl/'+str(f.relative_to(HERE/'rtl'))]
for a,b in zip(c['rows'],d['rows']):
 assert a['case']==b['case'] and a['profile']==b['profile'] and a['oracle']==b['oracle'] and a['payload_windows']==b['payload_windows']
 assert a['deterministic_repeats']==b['deterministic_repeats']==2
 old,new=(4041,3625) if a['case']=='transpose4' else (52125,52125)
 for r,cycles in [(a,old),(b,new)]:
  assert len(r['windows'])==7 and all(w['cycles']==cycles for w in r['windows'][2:])
  assert all(w['reads']==w['writes']==w['lines']==0 for w in r['windows'][2:])
def rec(directory,prefix,profile='0-0',case='transpose4'):
 return [dict(re.findall(r'(\w+)=(\w+)',l)) for l in (ROOT/directory/f'{case}-{profile}-0.log').read_text().splitlines() if l.startswith(prefix+' ')]
profiles=[]
for profile in ['0-0','2-9']:
 es,ns=[rec(x,'ISSUE_EDGE',profile) for x in [C,D]]
 assert len(es)==4041 and len(ns)==3625
 assert [(x['rpc']) for x in es if x['ret']=='1']==[(x['rpc']) for x in ns if x['ret']=='1'] and sum(x['ret']=='1' for x in ns)==1025
 aa,ww=[rec(C,x,profile) for x in ['LATE_ACCEPT','LATE_WRITE']]
 na,nw=[rec(D,x,profile) for x in ['LATE_ACCEPT','LATE_WRITE']]
 for pair in [(aa,ww),(aa,na),(ww,nw),(na,nw)]:
  assert len(pair[0])==len(pair[1])==384
  assert [(x['pc'],x['addr'],x['data']) for x in pair[0]]==[(x['pc'],x['addr'],x['data']) for x in pair[1]]
 assert all(int(w['edge'])==int(a['edge'])+2 for a,w in zip(na,nw))
 si,sd,sa=[rec(D,x,profile) for x in ['SECOND_ISSUE','SECOND_DATA','SECOND_ADDRESS']]
 assert len(si)==len(sd)==len(sa)==192
 assert rec(D,'SECOND_OWNERS',profile)==[dict(issued='192',data='192',address='192',accepted='192')]
 assert rec(D,'LATE_OWNERS',profile)==[dict(issued='192',address='192',exact_data='192',accepted='192')]
 def tables(edges,accepts,writes):
  t=defaultdict(list)
  for e in edges:
   if e['comp']=='1' and e['p2']=='1':t['completion',e['p2pc']].append(int(e['edge']))
   if e['pop']=='1':t['issue',e['opc']].append(int(e['edge']))
   if e['alu']=='1':
    key=('address',e['apc'])
    if not t[key] or (t[key][-1]!=int(e['edge'])-1 and int(e['edge'])-t[key][-1]>20):t[key].append(int(e['edge']))
  for kind,rr in [('accept',accepts),('write',writes)]:
   for e in rr:t[kind,e['pc']].append(int(e['edge']))
  return t
 oldt,newt=tables(es,aa,ww),tables(ns,na,nw)
 occurrence=Counter();pairs=[]
 for issue,data,address in zip(si,sd,sa):
  pc=issue['pc'];occ=occurrence[pc];occurrence[pc]+=1
  producer=issue['producer'];first=f'{int(pc,16)-4:08x}';otherproducer=f'{int(pc,16)-8:08x}';nextpc=f'{int(pc,16)+4:08x}'
  assert issue['rd']==data['rd']=='2' and data['producer']==producer and int(producer,16)+12==int(pc,16)
  assert data['pc']==address['pc']==pc and data['value']==address['data']
  assert int(issue['edge'])<int(data['edge'])<int(address['edge'])
  out=[]
  for table in [oldt,newt]:
   out.append(dict(r2_completion=table['completion',producer][occ],r3_completion=table['completion',otherproducer][occ],first_accept=table['accept',first][occ],first_write=table['write',first][occ],second_issue=table['issue',pc][occ],second_accept=table['accept',pc][occ],second_write=table['write',pc][occ],next_issue=table['issue',nextpc][occ]))
  old,new=out
  assert int(data['edge'])==new['r2_completion']
  assert new['second_accept']==new['first_accept']+1 and new['second_write']==new['first_write']+1
  assert old['second_accept']==old['first_accept']+4 and old['second_write']==old['first_write']+4
  accepts=[x for x in na if x['pc']==pc];assert accepts[occ]['data']==data['value'] and accepts[occ]['addr']==address['addr']
  pairs.append(dict(store=pc,occurrence=occ,allocation=issue,data=data,address=address,before=old,after=new))
 cp=rec(C,'CREDIT_WORK_PROFILE',profile)[2];np=rec(D,'CREDIT_WORK_PROFILE',profile)[2]
 keys=['read_stall','write_stall','load_lock','other_lock','empty','other']
 assert [int(cp[x]) for x in keys]==[737,192,479,64,1482,1087]
 assert [int(np[x]) for x in keys]==[673,0,255,64,1546,1087]
 assert sum(int(cp[k])-int(np[k]) for k in keys)==416
 profiles.append(dict(profile=profile,pairs=pairs,control_profile=cp,candidate_profile=np,actual_ordered_stores=384,second_owners=192))
 assert rec(C,'CREDIT_WORK_PROFILE',profile,case='matrix4')==rec(D,'CREDIT_WORK_PROFILE',profile,case='matrix4')
 assert rec(D,'SECOND_OWNERS',profile,case='matrix4')==[dict(issued='0',data='0',address='0',accepted='0')]
# Frozen stream fixture, same bytes and raw ordered events at both delays.
streams=[]
for profile,cn,dn,args in [('2:9','stream-control-retention','stream-candidate-retention',['+i_wait=2','+d_wait=9']),('0:0','stream-control-retention-0-0','stream-candidate-retention-0-0',[])]:
 rr=[]
 for name,identity in [(cn,ci),(dn,di)]:
  base='build/sim/cpu-store-second/'+name;r=read(base+'/result.json');m=read(base+'/manifest.json')
  assert r['status']=='PASS' and r['source']['source_id']==identity and m['runtime_args']==args
  for f,h in m['fixture_sha256'].items():assert sha(ROOT/base/'fixture'/f)==h
  assert all('issue_through_drain=71 ' in x for x in r['events'] if x.startswith('OVERLAP_SUMMARY') and 'window=0 ' not in x)
  assert any('accepted=448 physical_writes=448 completions=448 retired=448 independent_backing_words=16' in x for x in r['events'])
  rr.append(dict(result=r,manifest=m,path=base))
 assert rr[0]['manifest']['program_sha256']==rr[1]['manifest']['program_sha256'] and rr[0]['manifest']['fixture_sha256']==rr[1]['manifest']['fixture_sha256']
 assert rr[0]['result']['events']==rr[1]['result']['events']
 streams.append(dict(profile=profile,control=rr[0],candidate=rr[1]))
safety=[]
for name,identity in [('safety-control-final',ci),('safety-candidate-final',di),('safety-held-03',di)]:
 base='build/sim/cpu-store-second/'+name;r=read(base+'/result.json');m=read(base+'/manifest.json')
 assert r['status']=='PASS' and r['source']['source_id']==identity
 def focused(repeat):return [x for x in (ROOT/base/f'run-{repeat}.log').read_text().splitlines() if x.startswith(('SECOND_','PASS SECOND_','PASS LATE_','PASS LOAD_','OVERLAP_BOUNDARY'))]
 assert focused(0)==focused(1)
 if name!='safety-control-final':
  cases=[dict((k,int(v)) for k,v in re.findall(r'(\w+)=(\d+)',x)) for x in focused(0) if x.startswith('SECOND_SAFETY_CASE')];assert len(cases)==11
  assert [x['allocated'] for x in cases]==[0,1,0,1,0,0,1,0,1,0,0]
  assert [x['accepted'] for x in cases]==[1,1,1,1,1,0,0,0,0,0,0]
  assert any(x.startswith('SECOND_BANKED allocated=1 physical_rd=18') for x in focused(0))
  if name=='safety-held-03':
   held=next(x for x in focused(0) if x.startswith('SECOND_HELD_RETURN'))
   assert 'enabled=1' in held and int(re.search(r'saved_clocks=(\d+)',held)[1])>=2
 safety.append(dict(path=base,result=r,manifest=m,focused=focused(0)))
assert len({x['manifest']['program_sha256'] for x in safety})==1
neg=read('build/sim/cpu-store-second/stream-candidate-retention/wrong-physical-byte.json');assert neg['status']=='EXPECTED_FAILURE'
diag=read('build/sim/cpu-store-second/diagnostics-candidate-01/result.json');assert diag['status']=='PASS' and diag['source_id']==di and len(diag['rows'])==8
result=dict(decision='Retain isolated 4G: original transpose 4041 to 3625 (-416, -10.2945%); matrix52125 and stream71 unchanged. No physical fit or production adoption.',fixed_4F_source_id=ci,candidate_source_id=di,logical_added_bits=2,new_payload_flops=0,changed_files=changed,overlay_sha256={str(f.relative_to(ROOT)):sha(f) for f in (HERE/'rtl').rglob('*.sv')},helper_sha256={str(f.relative_to(ROOT)):sha(f) for f in HERE.iterdir() if f.suffix in ['.py','.v','.vh']},preflight=read('build/sim/cpu-store-second/preflight.json'),preflight_correction='Next LDR is independent in its base but writes R2; the existing WAW load scoreboard holds it until R2 completes. It issues c-1 versus c, not at the initially optimistic 148626.',workloads=[dict(control=a,candidate=b) for a,b in zip(c['rows'],d['rows'])],profiles=profiles,streams=streams,safety=safety,negative_physical=neg,diagnostics=diag,next_target=dict(workload='matrix4',target='Call/return target delivery and refill of the operand queue around original SMULL helper calls',matrix_empty=17995,matrix_total=52125,prior_4E_registered_handoffs=433,warning='Occupancy and event counts are not additive recoverable clocks; no new implementation or timing claim.'))
assert result['preflight']['source_id']==ci
assert sha(ROOT/result['preflight']['trace'])==result['preflight']['sha256']
result['failed_fixtures']=[]
for name,reason in [('safety-candidate-01','Observer required zero same-Rd allocation; actual later allocation correctly selected the younger ALU load, now checked by exact producer PC.'),('safety-held-01','Initial32-clock hold and inconsistent downstream bubbles did not establish retained-return coverage.'),('safety-held-02','Consistent32-clock hold still ended before cold-load return; accepted128-clock test spans70 retained-data clocks.')]:
 base='build/sim/cpu-store-second/'+name
 assert read(base+'/result.json')['status']=='INCOMPLETE'
 assert read(base+'/manifest.json')['source']['source_id']==di
 result['failed_fixtures'].append(dict(path=base,reason=reason,run0_sha256=sha(ROOT/base/'run-0.log')))
out=ROOT/'docs/evidence/cpu-store-second-20261116.json';out.write_text(json.dumps(result,indent=2)+'\n')
print('PASS fixed4F / 2-bit4G; 192 exact second-owner transfers;384 ordered actual writes; transpose3625/matrix52125/stream71; focus/held/banked/fault/8diagnostics:',out)
