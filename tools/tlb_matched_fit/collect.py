#!/usr/bin/env python3
"""Collect a completed matched fit, including negative timing artifacts."""
import argparse, hashlib,json,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/fit/tlb-matched-20261117';REPO='asturur/test_template_1'
p=argparse.ArgumentParser();p.add_argument('variant',choices=['5l','banked','banked-third']);p.add_argument('run');a=p.parse_args();third=a.variant=='banked-third'
out=ROOT/'build/fit/banked-third-20261118' if third else OUT/a.variant
load=lambda p:json.loads(p.read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def call(args):return subprocess.check_output(args,cwd=ROOT,text=True)
run=json.loads(call(['gh','run','view',a.run,'--repo',REPO,'--json','headSha,headBranch,status,conclusion,url,jobs']))
publication=load(out/'publication.json')
assert run['headSha']==publication.get('sha',publication.get('commit')) and run['headBranch']=='master'
(out/'run.json').write_text(json.dumps(run,indent=2)+'\n');assert run['status']=='completed'
for name in ['quartus-logs','ngage1-rbf']:
    d=out/(name+'-'+a.run)
    if not d.exists():subprocess.run(['gh','run','download',a.run,'--repo',REPO,'--name',name,'--dir',str(d)],check=True,cwd=ROOT)
reports=out/('quartus-logs-'+a.run);rbfdir=out/('ngage1-rbf-'+a.run)
if not (out/'summary.json').exists():
    with (out/'collect.log').open('w') as log:subprocess.run(['python3','tools/probe_retime_fit/collect.py',str(reports),'--output',str(out/'summary.json')],cwd=ROOT,check=True,stdout=log,stderr=subprocess.STDOUT)
s=load(out/'summary.json')
prior=OUT/'banked/verified-fit.json' if third else ROOT/'build/fit/combined-5jk-20261117/summary.json'
baseline=load(prior)['source']
actual=s['source'];info=load(rbfdir/'build-info.json')
if third:
    assert a.run=='44258633306' and publication['parent']==baseline['actual_commit']
    changed={n for n,h in actual['compiled_source_sha256'].items()
             if h!=baseline['compiled_source_sha256'].get(n)}
    assert changed=={'rtl/arm920/tlb.sv','rtl/arm/zap_dcache.sv'}
    for n in changed:
        raw=subprocess.check_output(['git','show',run['headSha']+':'+n],cwd=ROOT)
        assert hashlib.sha256(raw).hexdigest()==actual['compiled_source_sha256'][n]
else:
    q=load(out/'qualification.json')
    for n,h in q['compiled_RTL_sha256'].items():
        if n in actual['compiled_source_sha256']:assert h==actual['compiled_source_sha256'][n],n
assert actual['actual_commit']==info['commit']==run['headSha']
assert actual['seed']==info['fitter_seed']==42 and actual['debugger']==info['enable_debugger']==True
assert actual['compiled_source_sha256']==load(out/'expected-inputs.json') and len(actual['compiled_source_sha256'])==178
assert actual['effective_qsf']==baseline['effective_qsf']
for k in ['physical_pll_sha256','production_bram_sha256','unique_module_definitions']:assert actual[k]==baseline[k],k
assert all(len(v)==1 for v in actual['unique_module_definitions'].values())
for n,h in s['report_sha256'].items():assert sha(reports/n)==h,n
assert len(s['detailed_corners'])==8 and not s['scenario_errors']
subprocess.run(['python3','tools/check_sdram_io_registers.py',str(reports/'output_files/Template.fit.rpt')],check=True,cwd=ROOT)
def cells(path):return [[v.strip() for v in line.split(';')[1:-1]] for line in path.read_text(errors='replace').splitlines() if line.startswith(';')]
timing=reports/'output_files/timing/resident-store'
def clocks(mhz):return {r[0]:r[1:] for r in cells(timing/str(mhz)/'corner-1/clocks.rpt') if len(r)>12 and r[1] in ['Base','Generated']}
c78,c104=clocks(78),clocks(104);assert c78.keys()==c104.keys()
core=next(n for n in c78 if n.startswith('emu|pll|') and 'PLL_OUTPUT_COUNTER' in n)
assert abs(float(c78[core][1])-1000/78)<.002 and abs(float(c104[core][1])-1000/104)<.002
for n in c78:
    if not n.startswith('emu|pll|'):assert c78[n]==c104[n]
def exceptions(mhz):return [r for r in cells(timing/str(mhz)/'corner-1/constraints.rpt') if r and r[0].startswith('set_') and r[0]!='set_clock_uncertainty']
assert exceptions(78)==exceptions(104)
steps={x['name']:x['conclusion'] for j in run['jobs'] for x in j['steps']}
for n in ['Build with Quartus 17.0.2','Record effective master fit inputs','Analyze routed design at 78 and 104 MHz','Require SDRAM pin registers','Prepare ngage1 build output','Upload RBF (including failed timing)']:assert steps[n]=='success',n
rbf=rbfdir/'ngage1.rbf';assert 4_000_000<rbf.stat().st_size<6_000_000 and rbf.read_bytes()[:128]!=bytes(128)
fit=reports/'output_files/Template.fit.rpt';rows=cells(fit);columns=None;ram=[]
for r in rows:
    if any('Port A' in v for v in r) and any('Name' in v for v in r):columns=r
    if r and 'arm920_tlb_bank:bank|' in r[0] and 'M10K block' in r:
        ram.append(dict(zip(columns,r)) if columns and len(columns)==len(r) else dict(raw_cells=r))
assert len(ram)==(2 if a.variant=='5l' else 4),(len(ram),ram)
record=dict(status='PASS artifact and source verification',variant=a.variant,run=run,artifact=dict(path=str(rbf.relative_to(ROOT)),bytes=rbf.stat().st_size,sha256=sha(rbf),build_info=info,url=run['url']),source=actual,resources=s['resources'],cpu_hierarchy=s['cpu_hierarchy'],physical_TLB_RAM=ram,corners=s['detailed_corners'],normal_timing=s['normal_timing'],SDRAM_IO='PASS all 16 DQ input/output/OE registers',timing_gate=steps['Require passing timing'])
(out/'verified-fit.json').write_text(json.dumps(record,indent=2)+'\n')
print('PASS exact SHA,178inputs,RBF,seed42/debug,physicalPLL/BRAM,16SDRAM pin registers and8timing corners')
print('resources', {k:v for k,v in s['resources'].items() if k!='physical_rows'})
print('corners',[(c['MHz'],c['condition'].strip(),c['setup'],c['hold']) for c in s['detailed_corners']])
