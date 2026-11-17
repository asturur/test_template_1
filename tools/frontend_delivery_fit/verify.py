#!/usr/bin/env python3
"""Audit the collected exact5A fit; never dispatch, deploy or change Git state."""
from pathlib import Path
import argparse,hashlib,json,re
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--production',action='store_true');p.add_argument('--directory',type=Path,default=ROOT/'build/fit/frontend-5a-20261117');a=p.parse_args();out=a.directory.resolve()
load=lambda p:json.loads(p.read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
run=load(out/'run.json');expected=load(out/'expected.json');old=load(ROOT/'docs/evidence/cache-probe-admission-retime-fit-20261116.json');oldinputs=load(ROOT/'docs/evidence/cache-probe-admission-retime-fit-inputs-20261116.json')
reports=out/'quartus-logs-43985572525';s=load(out/'summary.json');actual=load(reports/'output_files/resident-fit-manifest.json');buildinfo=load(out/'rbf-43985572525/build-info.json');commit=load(out/'commit.json')
assert run['status']=='completed' and run['headSha']==actual['actual_commit']==buildinfo['commit']=='966270d981b0362412d055c0720a76db6ed4aca1'
assert commit['parents'][0]['sha']==oldinputs['actual_commit']=='418f6f824ab2e3353f71692382770433d5f0c093'
assert buildinfo['fitter_seed']==actual['seed']==42 and buildinfo['enable_debugger']==actual['debugger']==True
assert actual['payloads']==expected['payloads'] and len(actual['payloads'])==15
if a.production:
 for name,h in expected['payloads'].items():assert sha(ROOT/name)==h,name
 assert sha(ROOT/'rtl/ngage_bram.v')==expected['production_bram_sha256']
selected=dict(oldinputs['compiled_source_sha256']);selected.update(expected['payloads'])
assert actual['compiled_source_sha256']==selected and len(selected)==178
assert actual['effective_qsf']==oldinputs['effective_qsf']
assert actual['compiled_source_sha256']['rtl/ngage_bram.v']==expected['production_bram_sha256']
assert all(len(x)==1 for x in actual['unique_module_definitions'].values())
steps={x['name']:x for j in run['jobs'] for x in j['steps']}
for name in ['Build with Quartus 17.0.2','Record actual isolated fit inputs','Analyze retimed probe fit at 78 and 104 MHz','Require SDRAM pin registers','Prepare ngage1 build output','Upload build logs','Upload RBF (including failed timing)']:assert steps[name]['conclusion']=='success',name
assert steps['Require passing timing']['conclusion']=='failure' and s['scenario_errors']==''
rbf=out/'rbf-43985572525/ngage1.rbf';assert rbf.stat().st_size==4600916 and sha(rbf)=='8940a35518d6a61b36fe45b08f6bcfb4c8a056c6daeb4d0a1653bccbde250068'
def cells(path):return [[x.strip() for x in l.split(';')[1:-1]] for l in path.read_text().splitlines() if l.startswith(';')]
timing=reports/'output_files/timing/resident-store'
clocks=lambda f:{r[0]:r[1:] for r in cells(timing/f/'corner-1/clocks.rpt') if len(r)>12 and r[1] in ['Base','Generated']}
c78,c104=clocks('78'),clocks('104');assert c78.keys()==c104.keys()
for name in c78:
 if not name.startswith('emu|pll|'):assert c78[name]==c104[name],name
core=next(n for n in c104 if n.startswith('emu|pll|') and 'PLL_OUTPUT_COUNTER' in n)
assert abs(float(c78[core][1])-1000/78)<.002 and abs(float(c104[core][1])-1000/104)<.002
exceptions=lambda f:[r for r in cells(timing/f/'corner-1/constraints.rpt') if r and r[0].startswith('set_') and r[0]!='set_clock_uncertainty']
assert exceptions('78')==exceptions('104')
resources={}
for k,v in s['resources'].items():
 if k in old['resources']:resources[k]=dict(Stop3D=old['resources'][k]['Stop3D'],Step5A=v,delta=v-old['resources'][k]['Stop3D'])
corners=[]
for c in s['detailed_corners']:
 prior=next(x for x in old['corners'] if x['MHz']==c['MHz'] and x['condition']==c['condition'])
 row={k:c[k] for k in ['MHz','directory','condition','setup','hold','recovery','removal','min-pulse','checks','UCP']}
 row['setup_delta_vs_3D']=round(c['setup']-prior['setup'],3);row['global_first_path']=c['global_paths'][0]
 row['groups']={name:dict(matched_keepers=g['matched_keepers'],reported_path_count=len(g['reported_paths']),first_path=g['reported_paths'][0] if g['reported_paths'] else None) for name,g in c['groups'].items()}
 corners.append(row)
protection=load(out/'collection-protection-PASS.json');assert protection['HEAD']=='9c948da8da413a882e0fe8e559c380ea0cadabf4' and protection['index_entries_unchanged']
record=dict(run={k:run[k] for k in ['headSha','headBranch','status','conclusion','url']},artifact=dict(path=str(rbf.relative_to(ROOT)),bytes=rbf.stat().st_size,sha256=sha(rbf),build_info=buildinfo,uploads=load(out/'artifacts.json')),candidate_source_id=expected['candidate_source_id'],compile='success',timing_gate='failure',source=dict(actual_commit=actual['actual_commit'],parent=commit['parents'][0]['sha'],selected_inputs=178,all_selected_hashes_match_3D_plus_qualified_payloads=True,qualified_payloads=expected['payloads'],effective_qsf_identical_to_3D=True,production_bram_sha256=expected['production_bram_sha256'],unique_module_definitions=actual['unique_module_definitions']),resources=resources,block_memory_bits=s['resources']['block_memory_bits'],cpu_hierarchy=s['cpu_hierarchy'],normal_timing=s['normal_timing'],corners=corners,coverage=dict(unrelated_clocks_unchanged=True,explicit_exceptions_unchanged=True,core78=c78[core],core104=c104[core],scenario_errors='empty',SDRAM_pin_registers='PASS'),collection_protection=protection,report_sha256=s['report_sha256'],decision='Verified78MHz RBF collected despite timing failure. Owner explicitly authorized exact15-payload production/master consolidation after this verification; no deployment, retry or5B.')
(ROOT/'docs/evidence/cpu-frontend-delivery-fit-20261117.json').write_text(json.dumps(record,indent=2)+'\n')
(ROOT/'docs/evidence/cpu-frontend-delivery-fit-inputs-20261117.json').write_text(json.dumps(actual,indent=2)+'\n')
print('PASS verified RBF/commit/15payloads/all178inputs/physical78PLL;8routed corners;timing-only failure;collection protection')
