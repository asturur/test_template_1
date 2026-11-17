#!/usr/bin/env python3
"""Audit one registered load-scheduling experiment against fixed final 4B."""
from pathlib import Path
import hashlib,json,re,collections,subprocess
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
load=lambda p:json.loads(p.read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
four_b=load(ROOT/'docs/evidence/cpu-store-credit-20261116.json')
assert sha(ROOT/'tests/cpu/cpu_store_credit/rtl/arm920/cache_adapter.sv')==four_b['candidate_adapter_sha256']
for p,h in load(ROOT/'docs/evidence/cpu-store-overlap-20261116.json')['overlay_sha256'].items():assert sha(ROOT/p)==h,p
br=ROOT/'build/sim/spmark-payload'
cdir=br/'load-delivery-control-final';ndir=br/'load-delivery-candidate-final'
c=load(cdir/'result.json');n=load(ndir/'result.json');failed=load(br/'load-delivery-candidate-01/result.json')
prior=load(br/'store-credit-spare-01/result.json')
assert c['status']==n['status']==failed['status']=='PASS'
assert c['manifest']['source']['source_id']==four_b['candidate_source_id']
for key in ['harness_sha256','image_id','payload_sha256','original_rom_sha256']:assert c['manifest'][key]==n['manifest'][key],key
changed=[p for p,h in c['manifest']['source']['files'].items() if h!=n['manifest']['source']['files'][p]]
assert set(changed)=={'rtl/arm920/cache_access.sv','rtl/arm920/cache_adapter.sv'}
for p in (HERE/'rtl').rglob('*.sv'):assert n['manifest']['source']['files']['rtl/'+str(p.relative_to(HERE/'rtl'))]==sha(p)
hex_fields={'addr','aluaddr','p1addr','selected','hint','result_tag'}
def fields(line):
    out={}
    for k,v in re.findall(r'(\w+)=([^\s]+)',line):
        out[k]=int(v,16) if 'pc' in k or k in hex_fields else int(v) if v.isdigit() else v
    return out
def profile(d,iw,dw):
    p=d/f'transpose4-{iw}-{dw}-0.log';text=p.read_text()
    read=lambda prefix:[fields(x) for x in text.splitlines() if x.startswith(prefix+' ')]
    cases=read('LOAD_CASE');groups=collections.Counter((r['pc'],r['certified'],r['pending_first'],r['latency'],r['translation_wait'],r['admit'],r['fast']) for r in cases)
    return dict(cases=cases,classes=[dict(zip(['pc','certified','pending_first','latency','translation_wait','admit','fast','count'],[*k,v])) for k,v in groups.items()],load_profile=read('LOAD_PROFILE'),priority_profile=read('CREDIT_WORK_PROFILE'),probe_profile=read('PROBE_METRIC'),store_profile=read('STORE_METRIC'),edges=read('LOAD_EDGE')[:40],log_sha256=sha(p),repeat_log_sha256=sha(d/f'transpose4-{iw}-{dw}-1.log'))
workloads=[]
for a,b,old in zip(c['rows'],n['rows'],prior['rows']):
    assert a['case']==b['case']==old['case']=='transpose4' and a['profile']==b['profile']==old['profile']
    assert a['body_cycles_median']==4676 and b['body_cycles_median']==4644
    assert a['windows']==old['windows'] and a['payload_windows']==old['payload_windows']
    for key in ['program_sha256','oracle','payload_windows','deterministic_repeats']:assert a[key]==b[key],key
    for row in b['windows'][2:]:assert row['cycles']==4644 and all(row[k]==0 for k in ['reads','writes','lines','halfwords'])
    iw,dw=a['profile'].split(':');ca=profile(cdir,iw,dw);nb=profile(ndir,iw,dw)
    differences=[]
    assert len(ca['cases'])==len(nb['cases'])==416
    for x,y in zip(ca['cases'],nb['cases']):
        assert (x['pc'],x['addr'],x['certified'],x['pending_first'])==(y['pc'],y['addr'],y['certified'],y['pending_first'])
        assert x['external']==y['external']==0
        if x['latency']!=y['latency']:
            assert x['pc']==0x10002654 and x['latency']==4 and y['latency']==3
            differences.append(dict(pc=x['pc'],address=x['addr'],control=x['latency'],candidate=y['latency']))
    assert len(differences)==32
    uncert=[r for r in nb['cases'] if not r['certified']]
    assert len(uncert)==62 and all(r['lookup_hit']==1 for r in uncert)
    assert collections.Counter(r['latency'] for r in uncert)=={4:60,7:2}
    # Compact evidence keeps classified counts and representative edges;
    # all individual read owners remain in the immutable raw logs.
    for v in [ca,nb]:v['first_reads']=v.pop('cases')[:16]
    workloads.append(dict(profile=a['profile'],control_cycles=4676,candidate_cycles=4644,delta=-32,percent=100*(4644/4676-1),control=ca,candidate=nb,changed_read_owners=differences,oracle=a['oracle'],negative_output_controls=[c['qualification'],n['qualification']]))
looproot=ROOT/'build/sim/cpu-load-delivery'
loops={}
for name,source in [('store-control-01',c),('store-candidate-final',n),('peak-candidate-final',n)]:
    d=looproot/name;r=load(d/'result.json');m=load(d/'manifest.json');assert r['status']=='PASS'
    assert m['source']['files']==source['manifest']['source']['files']
    events=r['events'];segments=[fields(x) for x in events if x.startswith('OVERLAP_SUMMARY ')]
    assert all(x['issue_through_drain']==71 for x in segments[2:])
    loops[name]=dict(source_id=m['source']['source_id'],program_sha256=m['program_sha256'],segments=segments,boundary=[fields(x) for x in events if x.startswith(('OVERLAP_BOUNDARY ','OVERLAP_PEAK_CASES '))],pass_line=next(x for x in events if x.startswith('PASS overlap')),log_sha256=sha(d/'run-0.log'))
assert loops['store-control-01']['program_sha256']==loops['store-candidate-final']['program_sha256']==load(ROOT/'docs/evidence/cpu-store-overlap-20261116.json')['same_loop_guest_sha256']
pressure=load(looproot/'probe-pressure-final/result.json');assert pressure['status']=='PASS'
compat={name:load(ROOT/f'build/sim/load-delivery-{name}-final/result.json') for name in ['probe','admit']}
assert all(v['exit_code']==0 for v in compat.values())
negative=load(looproot/'store-candidate-final/wrong-physical-byte.json');assert negative['status']=='EXPECTED_FAILURE'
first=profile(br/'load-delivery-candidate-01','0','0');first.pop('cases')
e=dict(decision='Keep the bounded registered scheduler: transpose 4676 -> 4644 in both profiles; store loop stays 71. Exactly 32 certified waiting reads each save one clock. Next measured residual is 62 uncertified directory reads that are resident cache hits, plus unchanged load operand waits.',base=four_b['base'],fixed_4B_source_id=c['manifest']['source']['source_id'],candidate_source_id=n['manifest']['source']['source_id'],changed_files=changed,observer_sources_sha256={str(p.relative_to(ROOT)):sha(p) for p in [HERE/'payload_tb.v',HERE/'profile.vh']},overlay_sha256={str(p.relative_to(ROOT)):sha(p) for p in (HERE/'rtl').rglob('*.sv')},workloads=workloads,first_attempt=dict(cycles=[r['body_cycles_median'] for r in failed['rows']],reason='Saved 32 target clocks but lost 96 next-load immediate fast ACKs: data stalls +64 and empty-queue +4, total +68. The registered-result coverage guard restores P1 lookahead once P2 is already ready.',profile=first,source_id=failed['manifest']['source']['source_id']),store_loops=loops,pressure=pressure,compatibility={k:{'exit_code':v['exit_code'],'log_sha256':v['log_sha256']} for k,v in compat.items()},physical_wrong_byte=negative,raw_outputs={'transpose_control':str(cdir.relative_to(ROOT)),'transpose_candidate':str(ndir.relative_to(ROOT)),'first_attempt':'build/sim/spmark-payload/load-delivery-candidate-01','loops':str(looproot.relative_to(ROOT))})
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()==four_b['base']
assert subprocess.check_output(['git','branch','--show-current'],cwd=ROOT,text=True).strip()=='codex/ngage2-integration'
assert not subprocess.check_output(['git','diff','--name-only','--','rtl','Template.sv','Template.qsf','.github/workflows'],cwd=ROOT,text=True).strip()
(ROOT/'docs/evidence/cpu-load-delivery-20261116.json').write_text(json.dumps(e,indent=2)+'\n')
print('PASS fixed 4B, identical guest/oracles, exact 32-owner gain, 71-cycle stores, stale/older-fault qualification and production protection')
