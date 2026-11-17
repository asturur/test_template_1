#!/usr/bin/env python3
"""Collect the single master5B fit, source proof, routed scenarios and RBF."""
from pathlib import Path
import argparse,subprocess,json,hashlib,csv,collections
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--directory',type=Path,default=ROOT/'build/fit/cpu-owner-split-20261117');a=p.parse_args();out=a.directory.resolve();repo='asturur/test_template_1';run_id='44001480657'
load=lambda p:json.loads(p.read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def call(args):return subprocess.check_output(args,cwd=ROOT,text=True)
run=json.loads(call(['gh','run','view',run_id,'--repo',repo,'--json','headSha,headBranch,status,conclusion,url,jobs']))
assert run['headSha']=='419471d5cf85d2ca9d4cf6ff68a9652a1253ffd1' and run['headBranch']=='master'
(out/'run.json').write_text(json.dumps(run,indent=2)+'\n')
if run['status']!='completed':raise SystemExit('Fit is still running; no dispatch or retry performed')
artifacts=json.loads(call(['gh','api',f'repos/{repo}/actions/runs/{run_id}/artifacts']));(out/'artifacts.json').write_text(json.dumps(artifacts,indent=2)+'\n')
for name in ['quartus-logs','ngage1-rbf']:
 directory=out/(name+'-'+run_id)
 if not directory.exists():
  subprocess.run(['gh','run','download',run_id,'--repo',repo,'--name',name,'--dir',str(directory)],cwd=ROOT,check=True)
reports=out/('quartus-logs-'+run_id);rbfdir=out/('ngage1-rbf-'+run_id)
subprocess.run(['python3','tools/probe_retime_fit/collect.py',str(reports),'--output',str(out/'summary.json')],cwd=ROOT,check=True)
s=load(out/'summary.json');actual=load(reports/'output_files/resident-fit-manifest.json');expected=load(out/'expected-inputs.json');control=load(ROOT/'build/fit/frontend-5a-20261117/summary.json');ci=load(ROOT/'docs/evidence/cpu-frontend-delivery-fit-inputs-20261117.json');info=load(rbfdir/'build-info.json')
assert str(info['run_id'])==run_id
assert actual['actual_commit']==info['commit']==run['headSha'] and actual['seed']==info['fitter_seed']==42 and actual['debugger']==info['enable_debugger']==True
assert actual['effective_qsf']==ci['effective_qsf']
selected=dict(expected['compiled_source_sha256']);selected['Template.qsf']=ci['compiled_source_sha256']['Template.qsf'];assert actual['compiled_source_sha256']==selected and len(selected)==178
assert actual['physical_pll_sha256']==ci['compiled_source_sha256']['rtl/pll/pll_0002.v']
assert actual['production_bram_sha256']==ci['production_bram_sha256']
assert all(len(x)==1 for x in actual['unique_module_definitions'].values())
assert s['scenario_errors']=='' and len(s['detailed_corners'])==8
rbf=rbfdir/'ngage1.rbf';assert rbf.stat().st_size>4_000_000
steps={x['name']:x for j in run['jobs'] for x in j['steps']}
for name in ['Build with Quartus 17.0.2','Record effective master fit inputs','Analyze routed design at 78 and 104 MHz','Require SDRAM pin registers','Prepare ngage1 build output','Upload build logs','Upload RBF (including failed timing)']:assert steps[name]['conclusion']=='success',name
resources={k:dict(Step5A=v,Step5B=s['resources'][k],delta=s['resources'][k]-v) for k,v in control['resources'].items() if isinstance(v,int)}
def cells(path):return [[x.strip() for x in l.split(';')[1:-1]] for l in path.read_text().splitlines() if l.startswith(';')]
timing=reports/'output_files/timing/resident-store'
clocks=lambda f:{r[0]:r[1:] for r in cells(timing/f/'corner-1/clocks.rpt') if len(r)>12 and r[1] in ['Base','Generated']}
c78,c104=clocks('78'),clocks('104');assert c78.keys()==c104.keys()
for name in c78:
 if not name.startswith('emu|pll|'):assert c78[name]==c104[name],name
core=next(n for n in c104 if n.startswith('emu|pll|') and 'PLL_OUTPUT_COUNTER' in n);assert abs(float(c78[core][1])-1000/78)<.002 and abs(float(c104[core][1])-1000/104)<.002
exceptions=lambda f:[r for r in cells(timing/f/'corner-1/constraints.rpt') if r and r[0].startswith('set_') and r[0]!='set_clock_uncertainty']
assert exceptions('78')==exceptions('104')
corners=[]
for c in s['detailed_corners']:
 old=next(x for x in control['detailed_corners'] if x['MHz']==c['MHz'] and x['condition']==c['condition'])
 corners.append(dict(MHz=c['MHz'],condition=c['condition'],setup=c['setup'],delta_vs_5A=round(c['setup']-old['setup'],3),hold=c['hold'],recovery=c['recovery'],removal=c['removal'],min_pulse=c['min-pulse'],path=c['global_paths'][0],checks=c['checks'],UCP=c['UCP']))
negative=[x for x in csv.DictReader((timing/'78/corner-1/setup.csv').open()) if float(x['slack_ns'])<0]
record=dict(status='PASS artifact/source/analysis collection',run=run,artifact=dict(path=str(rbf.relative_to(ROOT)),bytes=rbf.stat().st_size,sha256=sha(rbf),build_info=info),source=dict(selected_inputs=178,matched_four_RTL_changes=True,effective_QSF_identical_to_5A=True,physical_PLL_and_BRAM_identical=True,actual_manifest_sha256=sha(reports/'output_files/resident-fit-manifest.json')),resources=resources,normal_timing=s['normal_timing'],corners=corners,negative_hot78_origins=dict(collections.Counter(x['from'] for x in negative)),coverage=dict(unrelated_clocks_unchanged=True,exceptions_unchanged=True,scenario_errors='',SDRAM_pin_registers='PASS'),timing_gate=steps['Require passing timing']['conclusion'],report_sha256=s['report_sha256'])
previous_path=ROOT/'docs/evidence/cpu-owner-split-fit-20261117.json'
if previous_path.exists():
 previous=load(previous_path)
 if previous['run']['headSha']==run['headSha'] and 'decision' in previous:record['decision']=previous['decision']
(ROOT/'docs/evidence/cpu-owner-split-fit-20261117.json').write_text(json.dumps(record,indent=2)+'\n');(ROOT/'docs/evidence/cpu-owner-split-fit-inputs-20261117.json').write_text(json.dumps(actual,indent=2)+'\n')
print('PASS matched master fit/source/physical78/8corners/RBF collection; timing gate:',record['timing_gate'])
