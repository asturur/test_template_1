#!/usr/bin/env python3
"""Audit actual5C/5D paired schedules, opportunity bound and checked workloads."""
from pathlib import Path
import json,re,hashlib,gzip,collections,argparse
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--partial',action='store_true');p.add_argument('--production',action='store_true');a=p.parse_args()
load=lambda p:json.loads(p.read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
read=lambda p:p.read_text() if p.exists() else gzip.open(str(p)+'.gz','rt').read();parse=lambda l:dict(re.findall(r'(\w+)=([^ ]+)',l))
paths=[ROOT/'build/sim/spmark-payload'/n for n in ['paired-control-final-02','paired-candidate-final-02']];manifests=[load(p/'manifest.json') for p in paths];results=[load(p/'result.json') for p in paths]
assert all(d['status']=='PASS' for d in results)
changes=[k for k,v in manifests[1]['source']['files'].items() if manifests[0]['source']['files'][k]!=v];assert changes==['rtl/arm/zap_shifter_multiply.sv']
for k in ['harness_sha256','image_id','payload_sha256','original_rom_sha256']:assert manifests[0][k]==manifests[1][k],k
work=[]
for old,new in zip(results[0]['rows'],results[1]['rows']):
 assert old['case']==new['case'] and old['profile']==new['profile'] and old['program_sha256']==new['program_sha256'] and old['oracle']==new['oracle']
 assert old['deterministic_repeats']==new['deterministic_repeats']==2
 work.append(dict(case=new['case'],profile=new['profile'],control=old['body_cycles_median'],candidate=new['body_cycles_median'],delta=new['body_cycles_median']-old['body_cycles_median']))
all_pairs=[];profiles=[];retired=[];summary=[]
for path in paths:
 lines=read(path/'matrix4-0-0-0.log').splitlines();rows=[parse(l) for l in lines if l.startswith('PAIR5D ')];starts=[i for i,x in enumerate(rows) if x['op']=='22' and x['state']=='1' and x['next']=='2'];assert len(starts)==1024
 pairs=[]
 for n,i in enumerate(starts):
  seg=rows[i:starts[n+1] if n+1<len(starts) else len(rows)];start=int(seg[0]['e']);rm,rs=int(seg[0]['rm'],16),int(seg[0]['rs'],16);signed=lambda x:x-(1<<32) if x>>31 else x;product=(signed(rm)*signed(rs))&((1<<64)-1);lo,hi=product&0xffffffff,product>>32
  ready=next(x for x in seg if x['state']=='4');low=next(x for x in seg if x['op']=='22' and x['advance']=='1');high=next(x for x in seg if x['op']=='23' and x['advance']=='1');consumer=next(x for x in seg if x['ipc']=='100011cc' and x['advance']=='1');low_consumer=next(x for x in seg if x['ipc']=='100011d0' and x['advance']=='1')
  lw=[x for x in seg if x['mempc']=='100011c8' and x['wen']=='1' and x['wa']=='2'];hw=[x for x in seg if x['mempc']=='100011c8' and x['wen']=='1' and x['wa']=='3'];assert len(lw)==len(hw)==1,(n,len(lw),len(hw))
  assert int(ready['product'],16)&((1<<64)-1)==product and int(low['result'],16)==lo and int(high['result'],16)==hi
  assert int(lw[0]['wd'],16)==lo and int(hw[0]['wd'],16)==hi
  assert int(consumer['shifted'],16)==hi and int(low_consumer['shifted'],16)==lo
  busy={int(x['e']) for x in seg if x['op']=='23' and x['busy']=='1'};holds={int(x['e']) for x in seg if x['oval']=='1' and x['lock']=='1' and x['shiftlock']=='1' and x['opc'] in ['100011d4','100011d8','100011dc']}
  pairs.append(dict(n=n,rm=rm,rs=rs,product=product,start=start,product_ready=int(ready['e'])-start,low_advance=int(low['e'])-start,high_advance=int(high['e'])-start,first_dependent_advance=int(consumer['e'])-start,first_dependent_PC='100011cc',first_dependent_value=hi,low_dependent_advance=int(low_consumer['e'])-start,low_write=int(lw[0]['e'])-start,high_write=int(hw[0]['e'])-start,high_busy=sorted(e-start for e in busy),dependent_holds=sorted(e-start for e in holds),overlap=len(busy&holds),union=len(busy|holds)))
 all_pairs.append(pairs);profiles.append(parse(next(x for x in lines if x.startswith('CREDIT_WORK_PROFILE index=2 '))));summary.append(parse(next(x for x in lines if x.startswith('PAIR5D_SUMMARY '))))
 retired.append([parse(x)['pc'] for x in lines if x.startswith('RET5D ')])
assert retired[0]==retired[1]
for old,new in zip(*all_pairs):
 assert all(old[k]==new[k] for k in ['n','rm','rs','product','low_advance','low_write'])
 assert old['high_busy']==[4,5] and new['high_busy']==[] and old['overlap']==new['overlap']==0
 assert old['dependent_holds']==[8,10,12] and new['dependent_holds']==[6,8,10]
 for k in ['high_advance','first_dependent_advance','low_dependent_advance','high_write']:assert old[k]-new[k]==2,(old['n'],k)
delta={k:int(profiles[1][k])-int(profiles[0][k]) for k in profiles[0] if k!='index'};assert sum(delta.values())==-2151
record=dict(base='78d53d4c129e761d979794c38398aa72ecf87f87',control_source_id=manifests[0]['source']['source_id'],candidate_source_id=manifests[1]['source']['source_id'],changed_files=changes,overlay_sha256={str(f.relative_to(ROOT)):sha(f) for f in (HERE/'rtl').rglob('*.sv')},logical_state_bits_added=1,payload_flops_added=0,opportunity=dict(workload_cycles=47887,direct_high_restart_clocks=2048,direct_percent=100*2048/47887,helper_hold_clocks=3072,explicit_overlap=0,union_clocks=5120,union_is_not_candidate_budget=True,first_consumer='MOV high half at100011cc; prior5C low-word sample belonged to100011d0'),workloads=work,profiles=dict(control=profiles[0],candidate=profiles[1],delta=delta),trace_summaries=summary,matched_retirement_PCs=len(retired[0]),retirement_PC_sha256=hashlib.sha256('\n'.join(retired[0]).encode()).hexdigest(),pairs=[dict(control=x,candidate=y) for x,y in zip(*all_pairs)])
if not a.partial:
 checks={}
 for name in ['unit-02','memory-01','memory-zero-02','irq-01','diagnostics-01']:
  d=ROOT/'build/sim/cpu-paired-delivery'/name;r=load(d/'result.json');assert r['status']=='PASS',name;checks[name]=dict(status='PASS',sha256=sha(d/'result.json'))
 jpeg=load(ROOT/'build/sim/jpeg-payload/paired-jpeg-01/result.json');assert jpeg['status']=='PASS' and all(x['observation']['body_cycles_median']==84353 for x in jpeg['rows'])
 for n in ['memory-01','memory-zero-02']:
  d=ROOT/'build/sim/cpu-paired-delivery'/n;ls=read(d/'run-0.log').splitlines();s=[parse(x) for x in ls if x.startswith('OVERLAP_SUMMARY ')];assert len(s)==7 and all(x['issue_through_drain']=='71' for x in s[2:])
  assert any(x.startswith('PASS overlap accepted_issue=448 accepted=448 physical_writes=448 completions=448 retired=448 independent_backing_words=16') for x in ls)
 negative=load(ROOT/'build/sim/cpu-paired-delivery/memory-01/wrong-physical-byte.json');assert negative['status']=='EXPECTED_FAILURE'
 for d in [ROOT/'build/sim/jpeg-payload/paired-jpeg-01',ROOT/'build/sim/cpu-paired-delivery/memory-01']:
  m=load(d/'manifest.json');assert m['source']['files']==manifests[1]['source']['files']
 profile=load(ROOT/'build/sim/cpu-paired-delivery/profile-01/result.json')
 assert profile['status']=='PASS'
 record.update(extra_profile=profile,qualification=checks,jpeg_cycles=84353,store_cycles=71,negative=negative,decision='Retain bounded general paired-ready state: matrix45736, transpose3591, JPEG84353, stream71. No fit or hardware work; investigate remaining shift consumer chain next.')
if a.production:
 import subprocess
 compiled={n:h for n,h in manifests[1]['source']['files'].items() if n.startswith('rtl/') and Path(n).suffix in ['.v','.sv','.svh']}
 for n,h in compiled.items():assert sha(ROOT/n)==h,n
 for n in ['Template.qsf','Template.sdc','rtl/pll/pll_0002.v','rtl/ngage_bram.v','files.qip']:
  assert (ROOT/n).read_bytes()==subprocess.check_output(['git','show',record['base']+':'+n],cwd=ROOT),n
 log=ROOT/'build/sim/cpu-paired-delivery/patch-replay.log';assert 'OK: rtl/arm ==' in log.read_text()
 record['production_adoption']=dict(compiled_CPU_RTL_inputs=len(compiled),compiled_RTL_matches_frozen_candidate=True,physical_PLL_constraints_QSF_BRAM_unchanged=True,patch='patches/zap/0077-retain-paired-multiply-result.patch',patch_replay_sha256=sha(log),physical_qualification='No5D fit; last fit5B predates5C/5D')
target=ROOT/('build/sim/cpu-paired-delivery/partial-evidence.json' if a.partial else 'docs/evidence/cpu-paired-delivery-20261117.json');target.write_text(json.dumps(record,indent=2)+'\n');print('PASS1024 actual products/ordered writes/advancing consumers and disjoint2151-cycle accounting',target)
