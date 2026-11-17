#!/usr/bin/env python3
"""Audit the bounded5F experiment, real group schedule and required regressions."""
from setup import *
import argparse,gzip,re,collections
p=argparse.ArgumentParser();p.add_argument('--production',action='store_true');a=p.parse_args()
load=lambda p:json.loads(p.read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
read=lambda p:p.read_text() if p.exists() else gzip.open(str(p)+'.gz','rt').read()
parse=lambda s:dict(re.findall(r'(\w+)=([^ ]+)',s))
paths=[ROOT/'build/sim/spmark-payload'/n for n in ['postindex-control-02','postindex-candidate-01']]
results=[load(p/'result.json') for p in paths];ms=[load(p/'manifest.json') for p in paths]
assert all(r['status']=='PASS' for r in results)
changed=[n for n,h in ms[0]['source']['files'].items() if ms[1]['source']['files'][n]!=h]
assert changed==['rtl/arm/zap_predecode_main.sv']
assert sha(HERE/'rtl/arm/zap_predecode_main.sv')==ms[1]['source']['files'][changed[0]]
for p,m in zip(paths,ms):
 for n,h in m['source']['files'].items():assert sha(p/'source'/n)==h
 for n,h in load(p/'fixture.json').items():assert sha(p/'fixture'/n)==h
 assert sha(p/'obj/Vbench')==m['executable_sha256']
for k in ['image_id','harness_sha256','programs','payload_sha256','original_images','original_rom_sha256','normal_import_link','profiles','repeat']:
 assert ms[0][k]==ms[1][k],k
assert results[0]['qualification']==results[1]['qualification']
assert all(x['wrong_output_rejected'] for x in results[1]['qualification'])
work=[];schedules=[]
expected={'matrix4':(45736,45736),'transpose4':(3591,3591),'fill16_tail':(2078,1332),'fill8_tail':(2172,1647)}
for old,new in zip(results[0]['rows'],results[1]['rows']):
 assert old['case']==new['case'] and old['profile']==new['profile'] and old['oracle']==new['oracle']
 assert old['program_sha256']==new['program_sha256'] and old['deterministic_repeats']==new['deterministic_repeats']==2
 case=old['case'];profile=old['profile'];ps=profile.replace(':','-')
 if case=='fill16_frame':want=(71259,71259) if profile=='0:0' else (201302,201302)
 else:want=expected[case]
 assert (old['body_cycles_median'],new['body_cycles_median'])==want
 logs=[read(p/f'{case}-{ps}-0.log').splitlines() for p in paths]
 retired=[[parse(s)['pc'] for s in ls if s.startswith('RET5F ')] for ls in logs]
 assert retired[0]==retired[1]
 for p,ls in zip(paths,logs):
  other=read(p/f'{case}-{ps}-1.log').splitlines()
  passive=lambda lines:[s for s in lines if s.startswith(('RET5F ','POST5F ','ACCEPT5F ','WRITE5F ','BASE5F ','DRAIN5F '))]
  assert passive(ls)==passive(other)
 cp=[parse(next(s for s in ls if s.startswith('CREDIT_WORK_PROFILE index=2 '))) for ls in logs]
 keys=['read_stall','write_stall','load_lock','other_lock','empty','other']
 delta={k:int(cp[1][k])-int(cp[0][k]) for k in keys};assert sum(delta.values())==want[1]-want[0]
 drain=[]
 for r,ls in zip([old,new],logs):
  ds=[parse(s) for s in ls if s.startswith('DRAIN5F ')];assert len(ds)==7
  drain.append([w['cycles']+int(d['extra']) for w,d in zip(r['windows'][2:],ds[2:])])
 if case=='fill16_frame':assert drain[0]==drain[1]==([71259]*5 if profile=='0:0' else [201407]*5)
 else:assert drain[0]==[w['cycles'] for w in old['windows'][2:]] and drain[1]==[w['cycles'] for w in new['windows'][2:]]
 work.append(dict(case=case,profile=profile,control=want[0],candidate=want[1],delta=want[1]-want[0],
   control_scored=[w['cycles'] for w in old['windows'][2:]],candidate_scored=[w['cycles'] for w in new['windows'][2:]],
   control_body_plus_first_empty=drain[0],candidate_body_plus_first_empty=drain[1],profile_delta=delta,
   matched_retirement_count=len(retired[0]),retirement_PC_sha256=hashlib.sha256('\n'.join(retired[0]).encode()).hexdigest()))
 if case not in ['fill16_tail','fill8_tail']:continue
 start=0x10002ae4 if case=='fill16_tail' else 0x10002a3c
 value=0x31a731a7 if case=='fill16_tail' else 0x5a5a5a5a
 for label,ls in zip(['control','candidate'],logs):
  es=[parse(s) for s in ls if s.startswith('POST5F ')]
  ac=[parse(s) for s in ls if s.startswith('ACCEPT5F ')]
  wr=[parse(s) for s in ls if s.startswith('WRITE5F ')]
  bw=[parse(s) for s in ls if s.startswith('BASE5F ')]
  rt=[parse(s) for s in ls if s.startswith('RET5F ')]
  main=[x for x in ac if start<=int(x['pc'],16)<start+32]
  assert len(main)==(504 if case=='fill16_tail' else 512)
  for n,x in enumerate(main):
   assert int(x['va'],16)==0x80004004+4*n and int(x['data'],16)==value and x['be']=='f'
   assert int(x['pc'],16)==start+(n%8)*4
  # A fallback accept has no certified result_way. Resolve that line's way
  # from a real indexed acceptance to the same resident line, possibly the
  # following word. No fills/maintenance occur in these warm tail windows.
  assert all(w['reads']==w['writes']==w['lines']==0 for w in (old if label=='control' else new)['windows'][2:])
  indexed={int(e['e']):e for e in es if e['accept']=='1' and e['pipe']=='1'}
  ways={int(x['va'],16)>>5:int(x['way']) for x in ac if int(x['e']) in indexed}
  group=[];previous_write=-1
  for n in range(8):
   pc=f'{start+n*4:08x}';x=next(x for x in main if x['pc']==pc);va=int(x['va'],16);at=int(x['e'])
   issue=next(e for e in es if e['opc']==pc and e['pop']=='1')
   known=next(e for e in es if e['spc']==pc and e['aval']=='1')
   advancing=next(e for e in es if e['spc']==pc and e['aval']=='1' and e['data']=='0')
   assert int(known['aaddr'],16)==va and int(known['aresult'],16)==va+4
   base=next(e for e in bw if e['pc']==pc);assert int(base['data'],16)==va+4
   way=ways[va>>5];mask=15<<((va>>2&7)*4)
   physical=next(e for e in wr if int(e['e'])>=at and int(e['e'])>previous_write and int(e['mask'],16)==mask and int(e['way'])==way and int(e['seg'])==(va>>5&7))
   assert (int(physical['line'],16)>>(va>>2&7)*32)&0xffffffff==value
   previous_write=int(physical['e']);ret=next(e for e in rt if e['pc']==pc)
   group.append(dict(pc=pc,va=va,data=value,issue=int(issue['e']),issue_base=int(issue['basenext'],16),
    address_known=int(known['e']),address_advances=int(advancing['e']),old_base=int(known['abase'],16),updated_base=va+4,
    accept=at,credit=int(x['credit']),physical_write=previous_write,physical_way=way,physical_mask=mask,
    base_commit=int(base['e']),retire=int(ret['e'])))
  offset=group[0]['retire'];assert [e['retire']-offset for e in group]==([0,3,6,9,12,15,18,24] if label=='control' else [0,1,2,3,4,5,6,14])
  schedules.append(dict(case=case,profile=profile,version=label,group=group,first_edges=es[:45],main_word_stores=len(main),
    accepted_PC_VA_data_sha256=hashlib.sha256(json.dumps([(x['pc'],x['va'],x['data']) for x in main]).encode()).hexdigest()))

out=ROOT/'build/sim/cpu-store-postindex';checks={}
for n in ['classify-01','memory-07','memory-zero-01']:
 r=load(out/n/'result.json');assert r['status']=='PASS';checks[n]=dict(status='PASS',result_sha256=sha(out/n/'result.json'))
assert 'vectors=12288' in load(out/'classify-01/result.json')['events'][0]
for n in ['memory-07','memory-zero-01']:
 r=load(out/n/'result.json');events=r['events']
 assert any(s.startswith('PASS POST_SAFETY cases=18 ') and 'precise_IRQ_prefix=14 ' in s for s in events)
 assert any('physical_writes=448 completions=448 retired=448 independent_backing_words=16' in s for s in events)
 ss=[parse(s) for s in events if s.startswith('OVERLAP_SUMMARY') and int(parse(s)['window'])>=2]
 assert len(ss)==5 and all(s['issue_through_drain']=='71' for s in ss)
 mf=load(out/n/'manifest.json')
 assert mf['source']['files']==ms[1]['source']['files']
assert load(out/'memory-zero-01/negative.json')['status']=='PASS'
assert all(r['status']=='EXPECTED_FAILURE' for r in load(out/'memory-zero-01/negative.json')['rows'])
failures={}
for p in [ROOT/'build/sim/spmark-payload/postindex-control-01',*[out/f'memory-0{n}' for n in range(1,7)],ROOT/'build/sim/jpeg-payload/postindex-jpeg-01']:
 r=load(p/'result.json');assert r['status']!='PASS';failures[str(p.relative_to(ROOT))]=r
compiled={n:h for n,h in ms[1]['source']['files'].items() if n.startswith('rtl/') and Path(n).suffix in ['.v','.sv','.svh']}
record=dict(status='PASS',decision='Retain bounded post-index admission: checked tail gains, unchanged requested regressions; no5E frontend change or donor work.',
 base=BASE,control_source_id=ms[0]['source']['source_id'],candidate_source_id=ms[1]['source']['source_id'],changed_files=changed,
 added_state_bits=0,new_address_or_forwarding_datapath=False,workloads=work,schedules=schedules,qualification=checks,
 negative=load(out/'memory-zero-01/negative.json'),preflight=load(out/'preflight.json'),failed_attempts=failures,
 optional_JPEG='Not simulated: PCH ENOSPC, then cached Docker image I/O errors. No new JPEG or additional diagnostic result claimed.',
 physical_PLL_MHz=78,registered_design_target_MHz=104,fit_CI_hardware_donor_jobs=False,
 next_priority='Trace line-transition completion/probe ownership and exposed frontend empty clocks, particularly the250-clock fill8 increase; no combined RTL change in5F.')
if a.production:
 for n,h in compiled.items():assert sha(ROOT/n)==h,n
 for n in ['Template.qsf','Template.sdc','rtl/pll/pll_0002.v','rtl/ngage_bram.v','files.qip']:
  assert (ROOT/n).read_bytes()==subprocess.check_output(['git','show',BASE+':'+n],cwd=ROOT)
 assert 'OK: rtl/arm ==' in (out/'patch-replay.log').read_text()
 record['production']=dict(compiled_RTL_inputs=len(compiled),matches_exact_measured_candidate=True,patch='patches/zap/0078-admit-postindexed-word-stores.patch',patch_replay_sha256=sha(out/'patch-replay.log'))
(ROOT/'docs/evidence/cpu-store-postindex-20261117.json').write_text(json.dumps(record,indent=2)+'\n')
print('PASS original fills/oracles/repeats/negatives; real8-store address/base/physical schedules;12,288class vectors;18post cases; precise IRQ;71-cycle warm stream')
