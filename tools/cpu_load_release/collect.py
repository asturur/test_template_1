#!/usr/bin/env python3
"""Collect exact release build, source/SDRAM proof and both timing scenarios."""
import argparse,hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/fit/combined-5jk-20261117';REPO='asturur/test_template_1'
p=argparse.ArgumentParser();p.add_argument('run');a=p.parse_args()
def load(p):return json.loads(p.read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def call(args):return subprocess.check_output(args,cwd=ROOT,text=True)
run=json.loads(call(['gh','run','view',a.run,'--repo',REPO,'--json','headSha,headBranch,status,conclusion,url,jobs']))
assert run['headSha']==load(OUT/'publication.json')['sha'] and run['headBranch']=='master'
(OUT/'run.json').write_text(json.dumps(run,indent=2)+'\n')
assert run['status']=='completed','build still active'
for name in ['quartus-logs','ngage1-rbf']:
 d=OUT/(name+'-'+a.run)
 if not d.exists():subprocess.run(['gh','run','download',a.run,'--repo',REPO,'--name',name,'--dir',str(d)],check=True,cwd=ROOT)
reports=OUT/('quartus-logs-'+a.run);rbfdir=OUT/('ngage1-rbf-'+a.run)
if not (OUT/'summary.json').exists():
 with (OUT/'collect.log').open('w') as log:
  subprocess.run(['python3','tools/probe_retime_fit/collect.py',str(reports),'--output',str(OUT/'summary.json')],cwd=ROOT,check=True,stdout=log,stderr=subprocess.STDOUT)
s=load(OUT/'summary.json');old=load(OUT/'baseline/summary.json')
for n,h in s['report_sha256'].items():assert sha(reports/n)==h
actual=load(reports/'output_files/resident-fit-manifest.json');baseline=load(OUT/'baseline/logs/output_files/resident-fit-manifest.json')
info=load(rbfdir/'build-info.json');q=load(OUT/'qualification.json')
assert actual['actual_commit']==info['commit']==run['headSha']
assert actual['seed']==info['fitter_seed']==42 and actual['debugger']==info['enable_debugger']==True
expected=dict(baseline['compiled_source_sha256']);expected['rtl/arm/zap_core.sv']=q['compiled_RTL_sha256']['rtl/arm/zap_core.sv']
assert actual['compiled_source_sha256']==expected and len(expected)==178
assert actual['effective_qsf']==baseline['effective_qsf']
assert actual['physical_pll_sha256']==baseline['physical_pll_sha256'] and actual['production_bram_sha256']==baseline['production_bram_sha256']
assert all(len(v)==1 for v in actual['unique_module_definitions'].values())
for n,h in q['compiled_RTL_sha256'].items():
 if n in actual['compiled_source_sha256']:assert h==actual['compiled_source_sha256'][n]
assert len(s['detailed_corners'])==8 and not s['scenario_errors']
subprocess.run(['python3','tools/check_sdram_io_registers.py',str(reports/'output_files/Template.fit.rpt')],check=True,cwd=ROOT)
def cells(path):return [[v.strip() for v in line.split(';')[1:-1]] for line in path.read_text().splitlines() if line.startswith(';')]
timing=reports/'output_files/timing/resident-store'
def clocks(mhz):return {r[0]:r[1:] for r in cells(timing/str(mhz)/'corner-1/clocks.rpt') if len(r)>12 and r[1] in ['Base','Generated']}
c78,c104=clocks(78),clocks(104);assert c78.keys()==c104.keys()
core=next(n for n in c78 if n.startswith('emu|pll|') and 'PLL_OUTPUT_COUNTER' in n)
assert abs(float(c78[core][1])-1000/78)<.002 and abs(float(c104[core][1])-1000/104)<.002
for n in c78:
 if not n.startswith('emu|pll|'):assert c78[n]==c104[n]
def exceptions(mhz):return [r for r in cells(timing/str(mhz)/'corner-1/constraints.rpt') if r and r[0].startswith('set_') and r[0]!='set_clock_uncertainty']
assert exceptions(78)==exceptions(104)
rbf=rbfdir/'ngage1.rbf';assert 4_000_000<rbf.stat().st_size<6_000_000 and rbf.read_bytes()[:128]!=bytes(128)
steps={x['name']:x['conclusion'] for j in run['jobs'] for x in j['steps']}
for name in ['Build with Quartus 17.0.2','Record effective master fit inputs','Analyze routed design at 78 and 104 MHz','Require SDRAM pin registers','Prepare ngage1 build output','Upload RBF (including failed timing)']:assert steps[name]=='success',name
corners=[]
for c in s['detailed_corners']:
 prior=next(o for o in old['detailed_corners']if(o['MHz'],o['condition'])==(c['MHz'],c['condition']))
 corners.append(dict(MHz=c['MHz'],condition=c['condition'],setup=c['setup'],hold=c['hold'],setup_delta=c['setup']-prior['setup'],hold_delta=c['hold']-prior['hold'],worst_path=c['global_paths'][0],groups=c['groups']))
record=dict(status='PASS artifact and source verification',run=run,artifact=dict(path=str(rbf.relative_to(ROOT)),bytes=rbf.stat().st_size,sha256=sha(rbf),build_info=info,url=run['url']),source=actual,resources=s['resources'],baseline_resources=old['resources'],corners=corners,normal_timing=s['normal_timing'],SDRAM_IO='PASS 16 input/output/OE registers',timing_gate=steps['Require passing timing'])
(OUT/'verified-fit.json').write_text(json.dumps(record,indent=2)+'\n')
print('PASS exact SHA,178inputs,RBF,seed42/debug,physicalPLL/BRAM,SDRAM registers and8timing corners')
print('resources',s['resources']);print('corners',[(c['MHz'],c['condition'],c['setup'],c['hold'])for c in corners])
