#!/usr/bin/env python3
"""Audit all1,024 actual SMULL owners and retain bounded5C schedules/results."""
from pathlib import Path
import json,re,gzip,hashlib,collections
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
load=lambda p:json.loads(p.read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
read=lambda p:p.read_text() if p.exists() else gzip.open(str(p)+'.gz','rt').read()
paths=[ROOT/'build/sim/spmark-payload'/x for x in ['product-control-final-03','product-candidate-final-02']]
results=[load(p/'result.json') for p in paths];manifests=[load(p/'manifest.json') for p in paths]
assert all(d['status']=='PASS' for d in results)
assert manifests[0]['source']['source_id']=='f3f199d1f9aa1eb0d995057d40be897c66caf399fc9378a41fdb9af255243181'
changed=[k for k,v in manifests[1]['source']['files'].items() if v!=manifests[0]['source']['files'][k]];assert changed==['rtl/arm/zap_shifter_multiply.sv']
for k in ['harness_sha256','image_id','payload_sha256','original_rom_sha256']:assert manifests[0][k]==manifests[1][k],k
work=[]
for old,new in zip(results[0]['rows'],results[1]['rows']):
 assert old['case']==new['case'] and old['profile']==new['profile'] and old['program_sha256']==new['program_sha256'] and old['oracle']==new['oracle']
 assert old['deterministic_repeats']==new['deterministic_repeats']==2
 work.append(dict(case=new['case'],profile=new['profile'],control=old['body_cycles_median'],candidate=new['body_cycles_median'],delta=new['body_cycles_median']-old['body_cycles_median']))
parse=lambda line:dict(re.findall(r'(\w+)=([^ ]+)',line))
profiles=[];all_pairs=[];summaries=[];retirement=[]
for path in paths:
 text=read(path/'matrix4-0-0-0.log');lines=text.splitlines();rows=[parse(x) for x in lines if x.startswith('MUL_EDGE ')];starts=[i for i,x in enumerate(rows) if x['op']=='22' and x['state']=='1' and x['next']=='2'];assert len(starts)==1024
 pairs=[]
 for num,start in enumerate(starts):
  seg=rows[start:starts[num+1] if num+1<len(starts) else len(rows)];first=int(seg[0]['e']);low=next(x for x in seg if x['state']=='16' and x['higher']=='0' and x['op']=='22');high=next(x for x in seg if x['state']=='16' and x['higher']=='1' and x['op']=='23');product=next(x for x in seg if x['state']=='4')
  rm,rs=int(seg[0]['rm'],16),int(seg[0]['rs'],16);signed=lambda n:n-(1<<32) if n>>31 else n;expected=(signed(rm)*signed(rs))&((1<<64)-1);lo=expected&0xffffffff;hi=expected>>32
  assert seg[0]['rn']==seg[0]['rh']=='00000000'
  assert int(product['product'],16)&((1<<64)-1)==expected and int(low['result'],16)==lo and int(high['result'],16)==hi
  lw=next(x for x in seg if x['wen']=='1' and x['dest_a']=='2' and x['mem']=='100011c8' and int(x['e'])>=int(low['e']))
  hw=next(x for x in seg if x['wen']=='1' and x['dest_a']=='3' and x['mem']=='100011c8' and int(x['e'])>=int(high['e']))
  consumer=next(x for x in seg if x['spc']=='100011cc' and int(x['e'])>int(low['e']))
  assert int(lw['data_a'],16)==lo and int(hw['data_a'],16)==hi and int(consumer['shsrc'],16)==lo
  pairs.append(dict(occurrence=num,rm=rm,rs=rs,product=expected,start=first,product_ready=int(product['e'])-first,low_ready=int(low['e'])-first,high_ready=int(high['e'])-first,low_write=int(lw['e'])-first,high_write=int(hw['e'])-first,consumer=int(consumer['e'])-first,states=[int(x['state']) for x in seg if x['op']=='22' and int(x['e'])<=int(low['e'])]))
 all_pairs.append(pairs)
 profiles.append(parse(next(x for x in lines if x.startswith('CREDIT_WORK_PROFILE index=2 '))))
 summaries.append(parse(next(x for x in lines if x.startswith('MUL_SUMMARY '))))
 retirement.append([parse(x)['rpc'] for x in lines if x.startswith('FE_EDGE ') and parse(x)['ret']=='1'])
assert retirement[0]==retirement[1]
for old,new in zip(*all_pairs):
 assert all(old[k]==new[k] for k in ['occurrence','rm','rs','product'])
 assert old['states']==[1,2,4,8,16] and new['states']==[1,2,4,16]
 for k in ['low_ready','high_ready','low_write','high_write','consumer']:assert old[k]-new[k]==1,(old['occurrence'],k)
assert summaries[0]['busy']=='6144' and summaries[1]['busy']=='5120'
profile_delta={k:int(profiles[1][k])-int(profiles[0][k]) for k in profiles[0] if k!='index'};assert sum(profile_delta.values())==-2146
checks={}
for name in ['arithmetic-final-03','irq-candidate-01','diagnostics-01','safety-01','safety-zero-final-03']:
 p=ROOT/'build/sim/cpu-product-bypass'/name;d=load(p/'result.json');assert d['status']=='PASS',name
 if name.startswith('safety'):
  lines=read(p/'run-0.log').splitlines();segments=[parse(x) for x in lines if x.startswith('OVERLAP_SUMMARY ')]
  assert len(segments)==7 and all(x['issue_through_drain']=='71' for x in segments[2:])
  assert any(x.startswith('PASS overlap accepted_issue=448 accepted=448 physical_writes=448 completions=448 retired=448 independent_backing_words=16') for x in lines)
 checks[name]=dict(status='PASS',sha256=sha(p/'result.json'))
jp=ROOT/'build/sim/jpeg-payload/product-jpeg-01';jpeg=load(jp/'result.json');assert jpeg['status']=='PASS';assert all(x['observation']['body_cycles_median']==84353 for x in jpeg['rows'])
for p in [jp,ROOT/'build/sim/cpu-product-bypass/safety-01']:
 m=load(p/'manifest.json');assert m['source']['files']==manifests[1]['source']['files']
negative=load(ROOT/'build/sim/cpu-product-bypass/safety-01/wrong-physical-byte.json');assert negative['status']=='EXPECTED_FAILURE'
record=dict(control_commit='419471d5cf85d2ca9d4cf6ff68a9652a1253ffd1',control_source_id=manifests[0]['source']['source_id'],candidate_source_id=manifests[1]['source']['source_id'],changed_files=changed,overlay_sha256={str(f.relative_to(ROOT)):sha(f) for f in (HERE/'rtl').rglob('*.sv')},added_state_bits=0,workloads=work,jpeg_cycles=84353,stream_cycles=71,profiles=dict(control=profiles[0],candidate=profiles[1],delta=profile_delta),multiply_summaries=summaries,paired_retirements=len(retirement[0]),pairs=[dict(control=a,candidate=b) for a,b in zip(*all_pairs)],qualification=checks,negative=negative,next_action=dict(rank1='General paired multiply result/consumer delivery, including the restarted high-half owner',high_busy_clocks=2048,helper_shift_lock_clocks=3072,warning='Overlapping ownership/lock observations are not additive savings; trace actual schedule before changing it',rank2='Frontend target/fetch to operand replenishment',matrix_empty_clocks=14765))
import sys,subprocess
if '--production' in sys.argv:
 compiled={name:h for name,h in manifests[1]['source']['files'].items() if name.startswith('rtl/') and Path(name).suffix in ['.sv','.v','.svh']}
 for name,h in compiled.items():assert sha(ROOT/name)==h,name
 fitted=load(ROOT/'docs/evidence/cpu-owner-split-fit-inputs-20261117.json');changes=[]
 for name,h in fitted['compiled_source_sha256'].items():
  if name=='Template.qsf':
   assert (ROOT/name).read_bytes()==subprocess.check_output(['git','show','419471d5:Template.qsf'],cwd=ROOT);continue
  if sha(ROOT/name)!=h:changes.append(name)
 assert changes==['rtl/arm/zap_shifter_multiply.sv']
 log=ROOT/'build/sim/cpu-product-bypass/patch-replay.log';assert 'OK: rtl/arm ==' in log.read_text()
 record['production_adoption']=dict(qualified_source_bundle=manifests[1]['source']['source_id'],compiled_CPU_RTL_inputs=len(compiled),compiled_RTL_matches_frozen_candidate=True,selected_changes_vs_matched_5B=changes,raw_QSF_unchanged_from_fitted_commit=True,effective_CI_profile=dict(seed=42,debugger=True,Quartus_edition_normalization='Standard to Lite'),physical_PLL_and_BRAM_unchanged=True,patch_replay_sha256=sha(log),patch='patches/zap/0076-skip-zero-addend-hold.patch',physical_qualification='5B only; 5C not fitted',retained_5B_commit='419471d5cf85d2ca9d4cf6ff68a9652a1253ffd1')
record['trace_label_clarification']=dict(reference='cpu-paired-delivery-20261117.json',historical_consumer_field='following low-half consumer100011d0',first_actual_dependent='high-half consumer100011cc',cycle_measurements_unchanged=True)
(ROOT/'docs/evidence/cpu-product-bypass-20261117.json').write_text(json.dumps(record,indent=2)+'\n');print('PASS all1024 paired arithmetic/writes/first-consumer schedules, identical retirement PCs, exact2146-cycle accounting and qualification')
