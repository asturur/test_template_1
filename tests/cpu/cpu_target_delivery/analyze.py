#!/usr/bin/env python3
"""Audit the single rejected5E iteration against exact accepted5D."""
from pathlib import Path
from collections import Counter
import hashlib, json, subprocess, re
from timeline import audit, read
from setup import BASE, ROOT, HERE

load = lambda p: json.loads(p.read_text())
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
arm = [ROOT/'build/sim/spmark-payload'/n for n in
       ['target-control-02', 'target-candidate-01']]
jpeg = [ROOT/'build/sim/jpeg-payload'/n for n in
        ['target-jpeg-control-01', 'target-jpeg-candidate-01']]
output = ROOT/'build/sim/cpu-target-delivery'
results = [load(p/'result.json') for p in arm+jpeg]
assert all(r['status'] == 'PASS' for r in results)
manifests = [load(p/'manifest.json') for p in arm+jpeg]
for p,m in zip(arm+jpeg,manifests):
    for name,digest in m['source']['files'].items():assert sha(p/'source'/name)==digest
    for name,digest in load(p/'fixture.json').items():assert sha(p/'fixture'/name)==digest
    assert sha(p/'tb.v')==m['harness_sha256']
    if 'executable_sha256' in m:assert sha(p/'obj/Vbench')==m['executable_sha256']
    assert sha(p/'fixture/tests/cpu/cpu_target_delivery/timeline.vh')==sha(HERE/'timeline.vh')
control, candidate = manifests[:2]
changes = [n for n,h in control['source']['files'].items()
           if candidate['source']['files'][n] != h]
assert changes == ['rtl/arm/zap_writeback.sv']
assert sha(HERE/'rtl/arm/zap_writeback.sv') == candidate['source']['files'][changes[0]]
assert manifests[2]['source']['files'] == control['source']['files']
assert manifests[3]['source']['files'] == candidate['source']['files']
for k in ['harness_sha256', 'image_id', 'programs', 'payload_sha256',
          'original_images', 'original_rom_sha256', 'normal_import_link', 'profiles', 'repeat']:
    assert control[k] == candidate[k], k
for k in ['harness_sha256', 'observer_sha256', 'image_id', 'programs', 'rom_sha256', 'payload_sha256']:
    assert manifests[2][k] == manifests[3][k], k
assert results[0]['qualification'] == results[1]['qualification']
assert all(x['wrong_output_rejected'] for x in results[1]['qualification'])

work = []
for old, new in zip(results[0]['rows'], results[1]['rows']):
    assert old['oracle'] == new['oracle'] and old['program_sha256'] == new['program_sha256']
    assert old['case'] == new['case'] and old['profile'] == new['profile']
    assert old['deterministic_repeats'] == new['deterministic_repeats'] == 2
    a,b = (45736,46932) if old['case'] == 'matrix4' else (3591,3537)
    assert old['body_cycles_median'] == a and new['body_cycles_median'] == b
    assert all(w['reads'] == w['writes'] == w['lines'] == 0
               for r in [old,new] for w in r['windows'][2:])
    work.append(dict(case=new['case'], profile=new['profile'], control=a, candidate=b, delta=b-a))
for old,new in zip(results[2]['rows'], results[3]['rows']):
    assert old['oracle'] == new['oracle'] and old['memory_profile'] == new['memory_profile']
    assert old['observation']['body_cycles_median'] == 84353
    assert new['observation']['body_cycles_median'] == 84014
    for row in [old,new]:
        ws=row['observation']['windows'];assert len(ws)==7 and all(w['retire_proxy']==22508 for w in ws)
        assert ws[2]['lines']==1 and ws[2]['reads']==8
        assert all(w['reads']==w['writes']==w['lines']==0 for w in ws[3:])
    work.append(dict(case=old['case'], profile=old['memory_profile'], control=84353, candidate=84014,
                     control_windows=old['observation']['windows'][2:], candidate_windows=new['observation']['windows'][2:], delta=-339))
for p in jpeg:
    assert 'guest result check failed' in read(p/'diffuse_m10_8x8_jpeg-wrong-output.log')

compiled = {n:h for n,h in control['source']['files'].items()
            if n.startswith('rtl/') and Path(n).suffix in ['.v','.sv','.svh']}
for n,h in compiled.items():
    assert sha(ROOT/n)==h, n
    assert hashlib.sha256(subprocess.check_output(['git','show',BASE+':'+n],cwd=ROOT)).hexdigest()==h
for n in ['Template.qsf','Template.sdc','rtl/pll/pll_0002.v','rtl/ngage_bram.v','files.qip']:
    assert (ROOT/n).read_bytes()==subprocess.check_output(['git','show',BASE+':'+n],cwd=ROOT)

timelines = {}; ledger = {}; raw_inputs = {}
event_columns = ['prediction','known','correction','source_issue','source_retire','request','ack',
                 'fetch','predecode','decode','issue','retire']
for case, paths, stem in [('matrix',arm,'matrix4'), ('jpeg',jpeg,'diffuse_m10_8x8_jpeg')]:
    timeline_profiles = []
    for profile in ['0-0','2-9']:
        ds=[]
        for label,p in zip(['control','candidate'],paths):
            path=p/f'{stem}-{profile}-0.log';d=audit(path);ds.append(d)
            (output/f'{case}-{label}-{profile}-timeline.json').write_text(json.dumps(d,indent=2)+'\n')
            prefix=lambda t:[s for s in t.splitlines() if s.startswith('TARGET5E ')]
            assert prefix(read(path))==prefix(read(p/f'{stem}-{profile}-1.log'))
            raw_inputs[str(path.relative_to(ROOT))]=hashlib.sha256(read(path).encode()).hexdigest()
        c,d=ds
        identity=lambda t:[(r['kind'],r['source'],r['occurrence'],r['target']) for r in t['records']]
        assert identity(c)==identity(d)
        assert c['retirement_PC_sha256']==d['retirement_PC_sha256']
        assert c['retirements']==d['retirements']==(14353 if case=='matrix' else 22508)
        if case=='jpeg':
            expected=load(paths[0]/'oracle.json')[stem]['pcs']
            for t in ds:
                actual={hex(int(k,16)):v for k,v in t['canonical_retirement_histogram'].items()
                        if 0x50500000<=int(k,16)<0x50600000}
                assert actual==expected
        delta={k:d['whole_buckets'].get(k,0)-c['whole_buckets'].get(k,0) for k in c['whole_buckets']}
        assert sum(delta.values())==(1196 if case=='matrix' else -339)
        correct=[(a,b) for a,b in zip(c['records'],d['records'])
                 if not a['needs_correction'] and a['hint_matches_actual']]
        assert len(correct)==(633 if case=='matrix' else 519)
        assert all(a['prediction'] is not None and b['prediction'] is not None and
                   a['request']-a['prediction']==b['request']-b['prediction']+1 for a,b in correct)
        timeline_profiles.append(dict(profile=profile,control={k:v for k,v in c.items() if k not in ['records','canonical_retirement_histogram']},
            candidate={k:v for k,v in d.items() if k not in ['records','canonical_retirement_histogram']},delta=delta,
            direct_one_clock_correct_prediction_occurrences=len(correct),direct_occurrences_are_not_wall_savings=True))
        # Compact, fully dynamic stage schedule: absolute stamps are anchored at
        # the first sampled edge, with event columns declared once.
        anchors=[t['records'][0]['known'] for t in ds]
        ledger[case+'-'+profile]=dict(anchors=anchors,rows=[
            [a['kind'],a['source'],a['occurrence'],a['target'],
             [a[k]-anchors[0] if a[k] is not None else None for k in event_columns],
             [b[k]-anchors[1] if b[k] is not None else None for k in event_columns]]
            for a,b in zip(c['records'],d['records'])])
    timelines[case]=timeline_profiles

# Transpose has no recognized BL calls; verify its complete retirement order too.
for profile in ['0-0','2-9']:
    pc=[]
    for p in arm:
        es=[dict(re.findall(r'(\w+)=([^ ]+)',s)) for s in read(p/f'transpose4-{profile}-0.log').splitlines() if s.startswith('TARGET5E ')]
        pc.append([e['rpc'] for e in es if e['ret']=='1'])
    assert pc[0]==pc[1] and len(pc[0])==1025

checks={}
for name in ['redirect-01','diagnostics-01','memory-01','memory-zero-01']:
    p=output/name;r=load(p/'result.json');assert r['status']=='PASS'
    checks[name]=dict(status='PASS',result_sha256=sha(p/'result.json'))
assert 'checks=38' in load(output/'redirect-01/result.json')['events'][-1]
assert len(load(output/'diagnostics-01/result.json')['rows'])==8
assert load(output/'diagnostics-01/result.json')['source_id']==candidate['source']['source_id']
unit_sources=load(output/'redirect-01/result.json')['source']
assert next(h for n,h in unit_sources.items() if n.endswith('/zap_writeback.sv'))==sha(HERE/'rtl/arm/zap_writeback.sv')
for name in ['memory-01','memory-zero-01']:
    p=output/name;mf=load(p/'manifest.json')
    for n,h in candidate['source']['files'].items():
        if n in compiled:assert mf['source']['files'][n]==h
    es=load(p/'result.json')['events']
    assert any('physical_writes=448 completions=448 retired=448 independent_backing_words=16' in e for e in es)
    ss=[e for e in es if e.startswith('OVERLAP_SUMMARY') and 'window=0 ' not in e]
    assert len(ss)==6 and all('issue_through_drain=71 ' in e for e in ss)
    assert mf['program_sha256']==load(ROOT/'build/sim/cpu-paired-delivery/memory-01/manifest.json')['program_sha256']
assert load(output/'memory-01/wrong-physical-byte.json')['status']=='EXPECTED_FAILURE'

protection=load(output/'protection.json')
for n,h in protection['unrelated_files'].items():assert sha(ROOT/n)==h,n
assert not subprocess.check_output(['git','diff','--cached','--binary'],cwd=ROOT)
assert not subprocess.check_output(['git','diff',BASE,'--','rtl','Template.qsf','Template.sdc','files.qip'],cwd=ROOT)
receipt=dict(status='PASS',decision='Reject the single registered-BTB handoff prototype; retain exact5D production CPU RTL.',
    base=BASE,control_source_id=control['source']['source_id'],candidate_source_id=candidate['source']['source_id'],
    changed_prototype_files=changes,production_RTL_changed=False,compiled_control_RTL_matches_exact5D=len(compiled),
    added_state_bits=0,physical_PLL_MHz=78,registered_design_target_MHz=104,new_fit_CI_or_hardware_access=False,
    workloads=work,timelines=timelines,event_columns=event_columns,dynamic_schedule_schema=['kind','source','occurrence','target','control_events','candidate_events'],
    dynamic_schedules=ledger,qualification=checks,negative_physical='EXPECTED_FAILURE',
    artifacts=[dict(path=str(p.relative_to(ROOT)),manifest_sha256=sha(p/'manifest.json'),result_sha256=sha(p/'result.json'),
                    executable_sha256=sha(p/'obj/Vbench')) for p in arm+jpeg],raw_trace_sha256=raw_inputs,
    next_question='Trace useful corrected-target preparation versus disposable BTB demand ownership, with phase-safe cancellation/priority; do not advance every prediction blindly.')
old5a=load(ROOT/'docs/evidence/cpu-frontend-delivery-20261117.json')['profiles'][0]['schedules']['candidate']['records']
old_samples=[next(r for r in old5a if r['kind']=='call' and r['pc']=='10002194'),
             next(r for r in old5a if r['kind']=='return' and r['occurrence']==1)]
new5d=load(output/'matrix-control-0-0-timeline.json')['records']
new_samples=[next(r for r in new5d if r['kind']=='call' and r['source']=='10002194'),
             [r for r in new5d if r['kind']=='return' and r['source']=='100011e4'][1]]
relative=lambda r:{k:r[k]-r['known'] for k in ['request','fetch','decode','issue']}
assert [relative(r) for r in old_samples]==[relative(r) for r in new_samples]
receipt['comparison_with_5A']=dict(second_helper_call=relative(new_samples[0]),second_helper_return=relative(new_samples[1]),
    unchanged_registered_CPU_redirect_schedule=True,donor_5C_retirement_intervals_are_not_stage_budgets=True)
witnesses={}
for case,paths,stem in [('matrix',arm,'matrix4'),('jpeg',jpeg,'diffuse_m10_8x8_jpeg')]:
    ds=[load(output/f'{case}-{label}-0-0-timeline.json') for label in ['control','candidate']]
    records=[d['records'] for d in ds]
    selected={'first_correct_prediction':next(i for i,r in enumerate(records[0]) if not r['needs_correction'] and r['hint_matches_actual'])}
    if case=='matrix':selected['first_helper_return']=next(i for i,r in enumerate(records[0]) if r['kind']=='return' and r['source']=='100011e4')
    for name,index in selected.items():
        sample={label:records[j][index] for j,label in enumerate(['control','candidate'])}
        if name=='first_helper_return':
            keys=['e','req','ack','addr','code','dc','dt','btbc','btbt','pc1','pc2','pc3','saved','state','owner','fast','tlb','trans']
            for j,(label,p) in enumerate(zip(['control','candidate'],paths)):
                known=sample[label]['known']
                edges=[dict(re.findall(r'(\w+)=([^ ]+)',s)) for s in read(p/f'{stem}-0-0-0.log').splitlines() if s.startswith('TARGET5E ')]
                sample[label+'_edges']=[{k:e[k] for k in keys} for e in edges if known-7<=int(e['e'])<=known+13]
        witnesses[case+'-'+name]=sample
receipt['witnesses']=witnesses
target=ROOT/'docs/evidence/cpu-target-delivery-20261117.json'
target.write_text(json.dumps(receipt,separators=(',',':'))+'\n')
print('PASS exact5D/source/guest/repeats; full dynamic transfers and retirement order;38target/8CPU/memory checks; REJECT prototype:',target)
