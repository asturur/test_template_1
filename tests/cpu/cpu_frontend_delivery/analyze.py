#!/usr/bin/env python3
"""Audit fixed4G vs corrected5A and align original dynamic matrix calls/returns."""
from setup import *
from collections import Counter,defaultdict
import re,gzip
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def raw(p):return p.read_bytes() if p.exists() else gzip.decompress(Path(str(p)+'.gz').read_bytes())
def read(p):return json.loads((ROOT/p).read_text())
def logs(directory,prefix,profile='0-0',case='matrix4'):
 return [dict(re.findall(r'(\w+)=(\w+)',l)) for l in raw(ROOT/directory/f'{case}-{profile}-0.log').decode().splitlines() if l.startswith(prefix+' ')]
C='build/sim/spmark-payload/frontend-control-01';A='build/sim/spmark-payload/frontend-candidate-01';D='build/sim/spmark-payload/frontend-candidate-02'
c,a,d=[read(x+'/result.json') for x in [C,A,D]]
ci,ai,di=[x['manifest']['source']['source_id'] for x in [c,a,d]]
assert ci==evidence['candidate_source_id']=='7b9a7dd28baccdfedfe75baaac91358c7751ed56d977fe348101738946e40244'
assert ai=='1b4eadbd9d100b51330b5fc2a87d5d6750b810325973bb74e5dd733075434470'
assert di=='1ddc7653903458d33e765e26bad69e1c8d817b2cab0920320b48d251ab2cb643'
for x in [c,a,d]:assert x['status']=='PASS' and len(x['rows'])==4
for k in ['programs','payload_sha256','original_images','original_rom_sha256','normal_import_link','profiles','repeat','harness_sha256','image_id']:assert c['manifest'][k]==a['manifest'][k]==d['manifest'][k],k
assert c['qualification']==a['qualification']==d['qualification'] and all(x['wrong_output_rejected'] for x in d['qualification'])
for directory,result in [(C,c),(A,a),(D,d)]:
 for f,h in result['manifest']['source']['files'].items():assert sha(ROOT/directory/'source'/f)==h
 changed=[f for f,h in c['manifest']['source']['files'].items() if result['manifest']['source']['files'][f]!=h]
 assert changed==([] if directory==C else ['rtl/arm/zap_writeback.sv'])
assert sha(HERE/'rtl/arm/zap_writeback.sv')==d['manifest']['source']['files']['rtl/arm/zap_writeback.sv']
for old,bad,new in zip(c['rows'],a['rows'],d['rows']):
 assert old['case']==bad['case']==new['case'] and old['profile']==bad['profile']==new['profile']
 assert old['oracle']==bad['oracle']==new['oracle'] and old['payload_windows']==bad['payload_windows']==new['payload_windows']
 cycles=(52125,52285,50033) if old['case']=='matrix4' else (3625,3591,3591)
 for r,n in zip([old,bad,new],cycles):
  assert r['deterministic_repeats']==2 and all(w['cycles']==n for w in r['windows'][2:])
  assert all(w['reads']==w['writes']==w['lines']==0 for w in r['windows'][2:])
def priority(e):
 if e['data']=='1':return 'data_write' if e['wr']=='1' else 'data_read'
 if e['shift']=='1':return 'shifter_busy'
 if e['oval']=='1' and e['ll']=='1':return 'load_lock'
 if e['oval']=='1' and e['sl']=='1':return 'shift_lock'
 if e['oval']=='0':return 'empty'
 return 'advance_other'
def intervals(es):
 result=[];start=0;occ=Counter()
 for i,e in enumerate(es):
  if e['ret']=='1':
   result.append(dict(pc=e['rpc'],occurrence=occ[e['rpc']],start=int(es[start]['e']),end=int(e['e']),clocks=i-start+1,buckets=dict(Counter(priority(x) for x in es[start:i+1]))));occ[e['rpc']]+=1;start=i+1
 return result
def delivery(es):
 # Every original BL-to-helper and helper BX in the timed fixed work.
 calls=[i for i,e in enumerate(es) if e['pv']=='1' and e['pst']=='0' and e['seq']=='0' and int(e['pins'],16)&0x0f000000==0x0b000000 and e['wt']=='100011c4']
 returns=[i for i,e in enumerate(es) if e['pv']=='1' and e['pst']=='0' and e['seq']=='0' and e['ppc']=='100011e4' and e['pins']=='e12fff1e']
 assert len(calls)==len(returns)==1024
 records=[];covered={};overlap=0
 for occurrence,(i,j) in enumerate(zip(calls,returns)):
  call=es[i];ret=es[j];assert int(ret['wt'],16)==int(call['ppc'],16)+4
  for kind,k,target in [('call',i,'100011c4'),('return',j,ret['wt'])]:
   e=es[k];actual=next(n for n in range(k,len(es)) if es[n]['pop']=='1' and es[n]['opc']==target)
   dec=next(n for n in range(k,actual+1) if es[n]['dv']=='1' and es[n]['dpc']==target)
   operand=next(n for n in range(k,actual+1) if es[n]['oval']=='1' and es[n]['opc']==target)
   # Some correctly predicted targets have already been requested/fetched before
   # predecode sees BL; search back to this call's previous return (not history).
   lower=records[-1]['issue_index'] if records else 0
   offer=next(n for n in range(lower,actual+1) if es[n]['req']=='1' and es[n]['addr']==target)
   fetch=next(n for n in range(lower,actual+1) if es[n]['fv']=='1' and es[n]['fpc']==target)
   clear=next((n for n in range(k,min(k+4,len(es))) if es[n]['dc']=='1' and es[n]['dt']==target),None) if e['wc']=='1' else None
   occdata=dict(occurrence=occurrence,kind=kind,pc=e['ppc'],target=target,opcode=e['pins'],predicted=e['pred'],taken=e['taken'],resolved_thumb=e['thumb'],needs_correction=e['wc']=='1',known=int(e['e']),clear=int(es[clear]['e']) if clear is not None else None,old_request=es[clear]['req'] if clear is not None else None,old_address=es[clear]['addr'] if clear is not None else None,old_ack=es[clear]['ack'] if clear is not None else None,request=int(es[offer]['e']),fetch=int(es[fetch]['e']),decode=int(es[dec]['e']),operand=int(es[operand]['e']),issue=int(es[actual]['e']),issue_index=actual,buckets=dict(Counter(priority(x) for x in es[k:actual])))
   records.append(occdata)
   for n in range(k,actual):
    if n in covered:overlap+=1
    else:covered[n]=kind
 assert overlap==0,'call/return delivery intervals overlap; use union attribution'
 return dict(records=records,covered_clocks=len(covered),exclusive_buckets={kind:dict(Counter(priority(es[n]) for n,v in covered.items() if v==kind)) for kind in ['call','return']},outside_buckets=dict(Counter(priority(e) for n,e in enumerate(es) if n not in covered)),whole_buckets=dict(Counter(priority(e) for e in es)),correction_counts=dict(Counter(x['kind'] for x in records if x['needs_correction'])))
profiles=[]
for profile in ['0-0','2-9']:
 traces=[logs(x,'FE_EDGE',profile) for x in [C,A,D]]
 ints=[intervals(es) for es in traces]
 assert all(len(x)==14353 for x in ints) and [[(r['pc'],r['occurrence']) for r in x] for x in ints].count([(r['pc'],r['occurrence']) for r in ints[0]])==3
 schedules=[delivery(es) for es in traces]
 assert [[(r['kind'],r['pc'],r['occurrence'],r['target']) for r in x['records']] for x in schedules].count([(r['kind'],r['pc'],r['occurrence'],r['target']) for r in schedules[0]['records']])==3
 cp,ap,dp=[logs(x,'CREDIT_WORK_PROFILE',profile)[2] for x in [C,A,D]]
 keys=['read_stall','write_stall','load_lock','other_lock','empty','other']
 assert [int(cp[k]) for k in keys]==[5503,2550,146,3088,17995,22843]
 assert [int(dp[k]) for k in keys]==[5567,2550,114,3088,15871,22843]
 assert sum(int(cp[k])-int(dp[k]) for k in keys)==2092
 # All 1024 call/return source identities and both samples' retirement order
 # are matched, not selected solely from the improved intervals.
 retirement_delta={}
 for label,rows in [('first_attempt',ints[1]),('candidate',ints[2])]:
  hist=defaultdict(Counter)
  for old,new in zip(ints[0],rows):hist[old['pc']][str(new['clocks']-old['clocks'])]+=1
  retirement_delta[label]={pc:dict(h) for pc,h in sorted(hist.items())}
 profiles.append(dict(profile=profile,schedules=dict(control=schedules[0],first_attempt=schedules[1],candidate=schedules[2]),control_profile=cp,first_attempt_profile=ap,candidate_profile=dp,retirement_count=14353,retirement_pc_order_sha256=hashlib.sha256(json.dumps([x['pc'] for x in ints[0]]).encode()).hexdigest(),retirement_interval_delta_histograms=retirement_delta))
# The full warm schedules are identical across delay profiles up to one time
# offset. Audit that equality, then store one copy with reconstruction offsets.
time_keys=['known','clear','request','fetch','decode','operand','issue']
for name in ['control','first_attempt','candidate']:
 rows0=profiles[0]['schedules'][name]['records'];rows1=profiles[1]['schedules'][name]['records']
 def normalized(rows):
  anchor=rows[0]['known']
  return [{k:(v-anchor if k in time_keys and v is not None else v) for k,v in r.items()} for r in rows]
 assert normalized(rows0)==normalized(rows1)
 summary=profiles[1]['schedules'][name]
 summary['records_from_profile']='0-0';summary['record_time_offset']=rows1[0]['known']-rows0[0]['known'];summary['record_count']=len(rows1)
 summary['relative_record_sha256']=hashlib.sha256(json.dumps(normalized(rows1),sort_keys=True).encode()).hexdigest()
 del summary['records']
# Cache attribution repeats exact main-run cycles and complete architectural work.
cache=[]
for name,identity,cycles in [('frontend-cache-control-01',ci,52125),('frontend-cache-candidate-01',ai,52285),('frontend-cache-candidate-02',di,50033)]:
 base='build/sim/spmark-payload/'+name;r=read(base+'/result.json');assert r['status']=='PASS' and r['manifest']['source']['source_id']==identity and r['rows'][0]['body_cycles_median']==cycles
 es=logs(base,'FE_EDGE');rows=logs(base,'IC_EDGE');clear=next(int(x['e']) for x in es if x['dc']=='1' and x['dt']=='10002188')
 cache.append(dict(path=base,source_id=identity,first_return_clear=clear,first_return=[x for x in rows if clear-3<=int(x['e'])<=clear+16]))
# Existing original Thumb block, same guest/ROM/math oracle, both profiles/repeats.
jpeg=[]
for name,identity,cycles in [('frontend-jpeg-control-01',ci,86428),('frontend-jpeg-candidate-01',ai,86076),('frontend-jpeg-candidate-02',di,84353)]:
 base='build/sim/jpeg-payload/'+name;r=read(base+'/result.json');assert r['status']=='PASS' and r['manifest']['source']['source_id']==identity and len(r['rows'])==2
 assert all(x['observation']['body_cycles_median']==cycles for x in r['rows'])
 for row in r['rows']:
  windows=row['observation']['windows'];assert len(windows)==7 and all(w['retire_proxy']==22508 for w in windows)
  assert all(w['cycles']==cycles for w in windows[3:])
  assert windows[2]['lines']==1 and windows[2]['reads']==8 and all(w['reads']==w['writes']==w['lines']==0 for w in windows[3:])
 badlog=ROOT/base/'diffuse_m10_8x8_jpeg-wrong-output.log'
 assert b'guest result check failed' in raw(badlog)
 jpeg.append(dict(path=base,result=r))
for k in ['programs','rom_sha256','payload_sha256','harness_sha256','observer_sha256','image_id']:assert len({json.dumps(x['result']['manifest'][k],sort_keys=True) for x in jpeg})==1,k
assert jpeg[0]['result']['rows'][0]['oracle']==jpeg[1]['result']['rows'][0]['oracle']==jpeg[2]['result']['rows'][0]['oracle']
streams=[]
for name,profile in [('stream-candidate-02','2:9'),('stream-candidate-02-zero','0:0')]:
 base='build/sim/cpu-frontend-delivery/'+name;r=read(base+'/result.json');assert r['status']=='PASS' and r['source']['source_id']==di
 assert all('issue_through_drain=71 ' in x for x in r['events'] if x.startswith('OVERLAP_SUMMARY') and 'window=0 ' not in x)
 assert any('physical_writes=448 completions=448 retired=448 independent_backing_words=16' in x for x in r['events'])
 ref=read('build/sim/cpu-store-second/'+('stream-candidate-retention' if profile=='2:9' else 'stream-candidate-retention-0-0')+'/manifest.json')
 m=read(base+'/manifest.json');assert m['runtime_args']==(['+i_wait=2','+d_wait=9'] if profile=='2:9' else []);assert m['program_sha256']==ref['program_sha256'] and ref['source']['source_id']==ci
 streams.append(dict(profile=profile,result=r,manifest=m,reference=ref))
negative=read('build/sim/cpu-frontend-delivery/stream-candidate-02/wrong-physical-byte.json');assert negative['status']=='EXPECTED_FAILURE'
redirect=read('build/sim/cpu-frontend-delivery/redirect-candidate-02/result.json');assert redirect['status']=='PASS' and 'checks=23' in redirect['events'][-1]
diag=read('build/sim/cpu-frontend-delivery/diagnostics-candidate-02/result.json');assert diag['status']=='PASS' and diag['source_id']==di and len(diag['rows'])==8
pre=read('build/sim/cpu-frontend-delivery/preflight.json');assert hashlib.sha256(raw(ROOT/pre['trace'])).hexdigest()==pre['sha256']
result=dict(decision='Retain corrected isolated5A: matrix50033, transpose3591, ThumbJPEG84353, store71; zero added state. No fit/production adoption.',fixed_4G_source_id=ci,first_attempt_source_id=ai,candidate_source_id=di,logical_added_state_bits=0,changed_files=['rtl/arm/zap_writeback.sv'],overlay_sha256={str(f.relative_to(ROOT)):sha(f) for f in (HERE/'rtl').rglob('*.sv')},helper_sha256={str(f.relative_to(ROOT)):sha(f) for f in HERE.iterdir() if f.suffix in ['.py','.v','.vh']},preflight=pre,workloads=[dict(control=x,first_attempt=y,candidate=z) for x,y,z in zip(c['rows'],a['rows'],d['rows'])],profiles=profiles,icache_attribution=cache,jpeg=jpeg,streams=streams,negative_physical=negative,redirect=redirect,diagnostics=diag,next_mainline_action='Remove one measured multi-cycle SMULL issue/forwarding recurrence in original matrix using this qualified5A as fixed control; retain original code and establish JPEG non-regression. Re-rank before broadening queues.')
storage=read('build/sim/cpu-frontend-delivery/trace-storage.json')
for r in storage:assert hashlib.sha256(raw(ROOT/r['path'])).hexdigest()==r['raw_sha256']
result['compressed_traces']=storage
result['fixture_snapshots']={}
for name in ['frontend-control-01','frontend-candidate-01','frontend-candidate-02','frontend-cache-control-01','frontend-cache-candidate-01','frontend-cache-candidate-02']:
 base=ROOT/'build/sim/spmark-payload'/name;h=json.loads((base/'fixture.json').read_text());m=json.loads((base/'manifest.json').read_text())
 for f,v in h.items():assert sha(base/'fixture'/f)==v
 main='cache_tb.v' if 'cache-' in name else 'payload_tb.v'
 assert h[main]==sha(base/'tb.v')==m['harness_sha256']
 result['fixture_snapshots'][name]=h
out=ROOT/'docs/evidence/cpu-frontend-delivery-20261117.json';out.write_text(json.dumps(result,indent=2)+'\n')
print('PASS exact4G / corrected5A; 1024 dynamic BL/BX pairs aligned; original matrix50033,transpose3591,ThumbJPEG84353,store71;23target cases and8diagnostics:',out)
