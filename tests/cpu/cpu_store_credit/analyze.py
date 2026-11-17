#!/usr/bin/env python3
"""Audit the one-spare-credit experiment and save compact measured evidence."""
from pathlib import Path
import hashlib,json,re,subprocess
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
load=lambda p:json.loads(p.read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
old=load(ROOT/'docs/evidence/cpu-store-overlap-20261116.json')
for p,h in old['overlay_sha256'].items():assert sha(ROOT/p)==h,p
base=ROOT/'build/sim/cpu-store-credit'
control=base/'control-final';candidate=base/'spare-final'
cm=load(control/'manifest.json');nm=load(candidate/'manifest.json')
assert cm['source']['source_id']==old['candidate_source_id']
assert cm['program_sha256']==nm['program_sha256']==old['same_loop_guest_sha256']
for k in ['harness_sha256','observer_sha256','image_id']:assert cm[k]==nm[k],k
changed=[p for p in cm['source']['files'] if cm['source']['files'][p]!=nm['source']['files'][p]]
assert changed==['rtl/arm920/cache_adapter.sv'],changed
assert nm['source']['files'][changed[0]]==sha(HERE/'rtl/arm920/cache_adapter.sv')
def fields(line):
    row={}
    for k,v in re.findall(r'(\w+)=([^\s]+)',line):
        row[k]=int(v,16) if 'pc' in k or k=='addr' else int(v) if v.isdigit() else v
    return row
def read_run(d):
    assert load(d/'result.json')['status']=='PASS'
    text=(d/'run-0.log').read_text()
    prefixes=['WINDOW ','OVERLAP_SUMMARY ','OVERLAP_HIST ','OVERLAP_COMMIT_HIST ','OVERLAP_ISSUE_HIST ','OVERLAP_EDGE ','OVERLAP_CREDIT ','OVERLAP_CREDIT_SUMMARY ','OVERLAP_BOUNDARY ','OVERLAP_PEAK_IRQ ','OVERLAP_PEAK_CASES ','RESULT ']
    result={p.strip():[fields(l) for l in text.splitlines() if l.startswith(p)] for p in prefixes}
    result['pass_line']=next(l for l in text.splitlines() if l.startswith('PASS overlap'))
    result['log_sha256']=sha(d/'run-0.log');result['repeat_sha256']=sha(d/'run-1.log')
    return result
c=read_run(control);n=read_run(candidate)
assert all(r['issue_through_drain']==102 for r in c['OVERLAP_SUMMARY'][2:])
assert all(r['issue_through_drain']==71 for r in n['OVERLAP_SUMMARY'][2:])
for kind in ['OVERLAP_HIST','OVERLAP_COMMIT_HIST']:
    for window in range(2,7):
        assert {r['gap']:r['count'] for r in c[kind] if r['window']==window}=={1:32,2:31}
        assert {r['gap']:r['count'] for r in n[kind] if r['window']==window}=={1:63}
assert n['OVERLAP_CREDIT_SUMMARY'][0]['peak']==2
stress={}
for name in ['control-peak-01','spare-peak-01']:
    d=base/name;r=read_run(d);s=load(d/'manifest.json')
    assert s['source']['files']==(cm if name.startswith('control') else nm)['source']['files']
    assert r['OVERLAP_PEAK_CASES'][0]['irq_count']==2 and r['OVERLAP_PEAK_CASES'][0]['fault_offer']>0 and r['OVERLAP_PEAK_CASES'][0]['active_load']>0
    stress[name]=r
assert load(base/'control-peak-01/manifest.json')['program_sha256']==load(base/'spare-peak-01/manifest.json')['program_sha256']
pressure=load(base/'pressure-02/result.json');assert pressure['status']=='PASS'
negative=load(candidate/'wrong-physical-byte.json');assert negative['status']=='EXPECTED_FAILURE'
br=ROOT/'build/sim/spmark-payload'
bc=load(br/'store-credit-control-01/result.json');bn=load(br/'store-credit-spare-01/result.json')
original4a=load(br/'store-overlap-candidate-final/result.json')
assert bc['status']==bn['status']=='PASS'
assert bc['manifest']['source']['files']==cm['source']['files'] and bn['manifest']['source']['files']==nm['source']['files']
for k in ['harness_sha256','image_id','payload_sha256','original_rom_sha256']:assert bc['manifest'][k]==bn['manifest'][k],k
workloads=[]
for a,b,prior in zip(bc['rows'],bn['rows'],original4a['rows']):
    assert a['case']==b['case']=='transpose4' and a['profile']==b['profile']==prior['profile']
    assert a['body_cycles_median']==b['body_cycles_median']==4676
    assert a['windows']==prior['windows'] and a['payload_windows']==prior['payload_windows']
    for key in ['oracle','program_sha256','payload_windows','deterministic_repeats']:assert a[key]==b[key],key
    iw,dw=a['profile'].split(':')
    def profile(name):
        text=(br/name/f'transpose4-{iw}-{dw}-0.log').read_text()
        return {prefix.strip():[fields(l) for l in text.splitlines() if l.startswith(prefix)] for prefix in ['STORE_METRIC ','PROBE_METRIC ','CREDIT_WORK_PROFILE ','CREDIT_WORK_TRACE ']}
    ca=profile('store-credit-control-01');cb=profile('store-credit-spare-01')
    assert ca==cb,'profile or first stall trace changed despite equal cycles'
    workloads.append(dict(case=a['case'],profile=a['profile'],control_cycles=4676,candidate_cycles=4676,oracle=a['oracle'],trace_and_profile=cb,negative_control=[bc['qualification'],bn['qualification']]))
e=dict(decision='Keep one spare credit as a measured store-stream primitive: 102 -> 71 cycles, no additional state bits. Transpose remains 4676; next workload dependency is serialized read availability/load-to-store dependency, not more store credits. No fit or production adoption.',base=cm['source']['commit'],fixed_4A_source_id=cm['source']['source_id'],candidate_source_id=nm['source']['source_id'],only_design_change=changed,candidate_adapter_sha256=sha(HERE/'rtl/arm920/cache_adapter.sv'),guest_sha256=cm['program_sha256'],harness_sha256=cm['harness_sha256'],observer_sha256=cm['observer_sha256'],control=c,candidate=n,loop_comparison=dict(stores=64,control_cycles=102,candidate_cycles=71,delta=-31,cycle_reduction_percent=100*(1-71/102),control_cycles_per_store=102/64,candidate_cycles_per_store=71/64,whole_marked_window={'control':123,'candidate':92}),peak_CPU_cases=stress,forced_pressure=dict(reason='Test-only four-clock physical-response publication delay; actual RAM writes remain real, mixed-port collisions poisoned; not a timed memory-model change',result=pressure),wrong_byte=negative,workloads=workloads,raw_outputs={'loop_control':str(control.relative_to(ROOT)),'loop_candidate':str(candidate.relative_to(ROOT)),'CPU_stress':['build/sim/cpu-store-credit/control-peak-01','build/sim/cpu-store-credit/spare-peak-01'],'pressure':'build/sim/cpu-store-credit/pressure-02','workload':['build/sim/spmark-payload/store-credit-control-01','build/sim/spmark-payload/store-credit-spare-01']})
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()==cm['source']['commit']
assert subprocess.check_output(['git','branch','--show-current'],cwd=ROOT,text=True).strip()=='codex/ngage2-integration'
assert not subprocess.check_output(['git','diff','--name-only','--','rtl','Template.sv','Template.qsf','.github/workflows'],cwd=ROOT,text=True).strip()
(ROOT/'docs/evidence/cpu-store-credit-20261116.json').write_text(json.dumps(e,indent=2)+'\n')
print('PASS fixed 4A/control identity, one-file candidate, guest bytes, histograms, physical oracles, peak stress, workload plateau and production protection')
