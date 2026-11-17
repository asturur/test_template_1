#!/usr/bin/env python3
"""Validate the final matched inputs and retain compact Step 4A measurements."""
from pathlib import Path
import hashlib,json,re,subprocess
ROOT=Path(__file__).resolve().parents[3]
load=lambda p:json.loads(p.read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
looproot=ROOT/'build/sim/cpu-store-overlap'
control=looproot/'control-final-02';candidate=looproot/'candidate-final-02'
cm=load(control/'manifest.json');nm=load(candidate/'manifest.json')
assert cm['program_sha256']==nm['program_sha256'] and cm['harness_sha256']==nm['harness_sha256'] and cm['observer_sha256']==nm['observer_sha256'] and cm['image_id']==nm['image_id']
for directory in [control,candidate]:assert load(directory/'result.json')['status']=='PASS'
benchroot=ROOT/'build/sim/spmark-payload'
bc=load(benchroot/'store-overlap-control-01/result.json');bn=load(benchroot/'store-overlap-candidate-final/result.json')
assert bc['status']==bn['status']=='PASS'
assert bc['manifest']['source']['files']==cm['source']['files']
assert bn['manifest']['source']['files']==nm['source']['files']
for key in ['harness_sha256','image_id','payload_sha256','original_rom_sha256']:
    assert bc['manifest'][key]==bn['manifest'][key],key
for path in (ROOT/'tests/cpu/cpu_store_overlap/rtl').rglob('*.sv'):
    relative='rtl/'+str(path.relative_to(ROOT/'tests/cpu/cpu_store_overlap/rtl'))
    assert nm['source']['files'][relative]==sha(path),relative
assert load(candidate/'wrong-physical-byte.json')['status']=='EXPECTED_FAILURE'
def fields(line):
    row={}
    for k,v in re.findall(r'(\w+)=([^\s]+)',line):
        row[k]=int(v,16) if 'pc' in k else int(v) if v.isdigit() else v
    return row
def parse(directory):
    text=(directory/'run-0.log').read_text()
    select=lambda prefix:[fields(x) for x in text.splitlines() if x.startswith(prefix)]
    return dict(windows=select('WINDOW '),segments=select('OVERLAP_SUMMARY '),histograms=select('OVERLAP_HIST '),boundary=select('OVERLAP_BOUNDARY '),edges=select('OVERLAP_EDGE '),first_pair=select('PAIR '),pass_line=next(x for x in text.splitlines() if x.startswith('PASS overlap')),total=select('RESULT '),log_sha256=sha(directory/'run-0.log'),repeat_sha256=sha(directory/'run-1.log'))
c=parse(control);n=parse(candidate)
assert all(x['issue_through_drain']==197 for x in c['segments'][2:])
assert all(x['issue_through_drain']==102 for x in n['segments'][2:])
assert len(c['windows'])==len(n['windows'])==7
assert all(x['cycles']==218 for x in c['windows'][2:]) and all(x['cycles']==123 for x in n['windows'][2:])
for row in c['windows'][2:]+n['windows'][2:]:assert row['retire_proxy']==73 and all(row[k]==0 for k in ['reads','writes','lines','halfwords'])
for row in c['boundary']+n['boundary']:assert row['irq']==row['abort']==1 and row['following_load']==row['byte_transition']=='PASS'
workloads=[]
for old,new in zip(bc['rows'],bn['rows']):
    assert old['case']==new['case']=='transpose4' and old['profile']==new['profile']
    assert old['program_sha256']==new['program_sha256']
    assert old['oracle']==new['oracle'] and old['payload_windows']==new['payload_windows']
    assert old['deterministic_repeats']==new['deterministic_repeats']
    iw,dw=new['profile'].split(':')
    metric=lambda name:[fields(x) for x in (benchroot/name/f'transpose4-{iw}-{dw}-0.log').read_text().splitlines() if x.startswith('STORE_METRIC ')]
    workloads.append(dict(case=new['case'],profile=new['profile'],control_cycles=old['body_cycles_median'],candidate_cycles=new['body_cycles_median'],cycle_delta=new['body_cycles_median']-old['body_cycles_median'],cycle_change_percent=100*(new['body_cycles_median']/old['body_cycles_median']-1),control_store_metrics=metric('store-overlap-control-01'),candidate_store_metrics=metric('store-overlap-candidate-final'),wrong_output_controls=[bc['qualification'],bn['qualification']],oracle=new['oracle']))
e=dict(decision='Working measured intermediate: preserve isolated two-credit candidate; no production/CI/deployment or timing claim. Next measured dependency is registered credit return: 32 one-clock and 31 two-clock gaps per warmed 64-store sequence.',base=cm['source']['commit'],overlay_sha256={str(p.relative_to(ROOT)):sha(p) for p in (ROOT/'tests/cpu/cpu_store_overlap/rtl').rglob('*.sv')},control_source_id=cm['source']['source_id'],candidate_source_id=nm['source']['source_id'],same_loop_guest_sha256=cm['program_sha256'],same_loop_harness_sha256=cm['harness_sha256'],same_loop_observer_sha256=cm['observer_sha256'],control=c,candidate=n,loop_comparison=dict(stores=64,issue_through_drained_write={'control':197,'candidate':102,'cycle_reduction_percent':100*(1-102/197),'control_cycles_per_store':197/64,'candidate_cycles_per_store':102/64},marked_window_including_following_load_and_byte_checks={'control':218,'candidate':123,'cycle_reduction_percent':100*(1-123/218)}),workloads=workloads,negative_control=load(candidate/'wrong-physical-byte.json'),compatibility=dict(qualification='build/sim/store-overlap-qualification-01/result.json',probe='build/sim/store-overlap-probe-final/result.json'),raw_outputs={'loop_control':str(control.relative_to(ROOT)),'loop_candidate':str(candidate.relative_to(ROOT)),'workload_control':'build/sim/spmark-payload/store-overlap-control-01','workload_candidate':'build/sim/spmark-payload/store-overlap-candidate-final'})
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()==cm['source']['commit']
assert subprocess.check_output(['git','branch','--show-current'],cwd=ROOT,text=True).strip()=='codex/ngage2-integration'
assert not subprocess.check_output(['git','diff','--name-only','--','rtl','Template.sv','Template.qsf','.github/workflows'],cwd=ROOT,text=True).strip()
(ROOT/'docs/evidence/cpu-store-overlap-20261116.json').write_text(json.dumps(e,indent=2)+'\n')
print('PASS exact matched source/program/harness/oracle identities, loop speedup, workload speedup and production protection')
