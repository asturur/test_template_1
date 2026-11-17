#!/usr/bin/env python3
"""Validate collected Stop 3D evidence and save its compact durable record."""
from pathlib import Path
import argparse, collections, hashlib, json, re, subprocess

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/fit/probe-retime-20261116'
RAW=OUT/'candidate'
p=argparse.ArgumentParser();p.add_argument('--decision',required=True);a=p.parse_args()
load=lambda p:json.loads(p.read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
run=load(OUT/'run.json');candidate=load(OUT/'candidate-summary.json')
old=load(ROOT/'docs/evidence/cache-resident-store-pipeline-fit-20261116.json')
stock=load(ROOT/'build/fit/resident-store-20261116/control-summary.json')
manifest=load(RAW/'output_files/resident-fit-manifest.json')
preflight=load(OUT/'preflight-container-manifest.json')
assert run['status']=='completed'
assert run['headSha']==manifest['actual_commit']=='418f6f824ab2e3353f71692382770433d5f0c093'
assert manifest['compiled_source_sha256'].keys()==preflight['compiled_source_sha256'].keys()
for name,value in manifest['compiled_source_sha256'].items():
    if name!='Template.qsf':assert value==preflight['compiled_source_sha256'][name],name
# Quartus writes its own edition metadata during compilation. Require this
# exact one-line change, rather than exempting the effective QSF from proof.
qsf_before=preflight['effective_qsf']
qsf_after=manifest['effective_qsf']
assert qsf_before.replace('LAST_QUARTUS_VERSION "17.0.2 Standard Edition"','LAST_QUARTUS_VERSION "17.0.2 Lite Edition"')==qsf_after
qsf_normalization={'file':'Template.qsf','only_change':'LAST_QUARTUS_VERSION Standard Edition -> Lite Edition by Quartus','preflight_sha256':preflight['compiled_source_sha256']['Template.qsf'],'postcompile_sha256':manifest['compiled_source_sha256']['Template.qsf'],'all_other_QSF_bytes_unchanged':True}
assert all(len(v)==1 for v in manifest['unique_module_definitions'].values())
assert candidate['scenario_errors']==''
assert 'clock-coverage-PASS.txt' in candidate['scenarios']['104']['coverage_files']
steps={s['name']:s for j in run['jobs'] for s in j['steps']}
for name in ['Build with Quartus 17.0.2','Record actual isolated fit inputs','Analyze retimed probe fit at 78 and 104 MHz','Require SDRAM pin registers','Upload build logs']:
    assert steps[name]['conclusion']=='success',(name,steps[name])

def cells(path):
    return [[v.strip() for v in line.split(';')[1:-1]] for line in path.read_text(errors='replace').splitlines() if line.startswith(';')]

tr=RAW/'output_files/timing/resident-store'
clockrows=lambda f:{r[0]:r[1:] for r in cells(tr/f/'corner-1/clocks.rpt') if len(r)>12 and r[1] in ['Base','Generated']}
cl78=clockrows('78');cl104=clockrows('104')
assert cl78.keys()==cl104.keys()
for name in cl78:
    if not name.startswith('emu|pll|'):assert cl78[name]==cl104[name],name
    else:assert cl78[name][13:]==cl104[name][13:],name
core=next(n for n in cl104 if n.startswith('emu|pll|') and 'PLL_OUTPUT_COUNTER' in n)
assert abs(float(cl104[core][1])-1000/104)<.002
exception_rows=lambda f:[r for r in cells(tr/f/'corner-1/constraints.rpt') if r and r[0].startswith('set_') and r[0]!='set_clock_uncertainty']
assert exception_rows('78')==exception_rows('104')
protected=load(OUT/'protected-checkout-before.json')
for path,value in protected.items():
    if path in ['HEAD','branch','index_entries_sha256']:continue
    assert sha(ROOT/path)==value,path
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()==protected['HEAD']
assert subprocess.check_output(['git','branch','--show-current'],cwd=ROOT,text=True).strip()==protected['branch']
assert hashlib.sha256(subprocess.check_output(['git','ls-files','--stage'],cwd=ROOT)).hexdigest()==protected['index_entries_sha256']

def compact(path):
    return {**{k:v for k,v in path.items() if k!='control_hops'},'named_control_hops':list(path.get('control_hops',{}))}

corners=[]
for corner in candidate['detailed_corners']:
    row={k:v for k,v in corner.items() if k not in ['groups','global_paths','recovery_paths']}
    row['groups']={name:{'report_result':group['report_result'],'matched_keepers':group['matched_keepers'],'first_path':compact(group['reported_paths'][0]) if group['reported_paths'] else None,'reported_path_count':len(group['reported_paths']),'resolved_keepers_sha256':group['resolved_keepers_sha256']} for name,group in corner['groups'].items()}
    families=collections.Counter(re.sub(r'\[\d+\]','[]',p['To Node'].split('|')[-1].split('_OTERM')[0].split('~')[0]) for p in corner['global_paths'])
    row['global_top100_endpoint_families']=dict(families)
    groups={}
    for path in corner['global_paths']:
        to=path['To Node'];source=path['From Node']
        family=('CPU exclusion' if 'block_cpu' in to else
                'D-tag RAM-B' if 'u_data_cache' in to and 'packed_dirty_tags.tag_ram' in to else
                'SWP to board/peripheral' if 'swp_lock_active' in source else
                'D-adapter saved fault' if 'u_data_cache' in to and 'saved_external_' in to else 'other')
        groups.setdefault(family,[]).append(path)
    row['global_top100_families']={name:{'reported_count':len(paths),'first_path':compact(paths[0])} for name,paths in groups.items()}
    row['global_first_path']=compact(corner['global_paths'][0])
    row['recovery_first_path']=compact(corner['recovery_paths'][0]) if corner['recovery_paths'] else None
    prior=next(c for c in old['corners'] if c['MHz']==corner['MHz'] and c['condition']==corner['condition'])
    row['delta_vs_3B']={kind:corner[kind]-prior['min_pulse' if kind=='min-pulse' else kind] for kind in ['setup','hold','recovery','removal','min-pulse']}
    corners.append(row)
resources={k:dict(stock=stock['resources'][k],Stop3B=old['resources'][k]['candidate'],Stop3D=v,delta_vs_3B=v-old['resources'][k]['candidate']) for k,v in candidate['resources'].items() if k in old['resources']}
evidence={'decision':a.decision,'run':{k:run[k] for k in ['headSha','headBranch','status','conclusion','url']},'submission':load(OUT/'submission.json'),'direct_tree_diff_vs_3B':load(OUT/'tree-diff-3b.json'),'resources':resources,'planning_headroom':{'ALMs':40450-candidate['resources']['ALMs'],'M10Ks':521-candidate['resources']['M10Ks']},'cpu_hierarchy':candidate['cpu_hierarchy'],'normal_78':{'stock':stock['normal_timing'],'Stop3B':old['normal_78']['candidate'],'Stop3D':candidate['normal_timing']},'corners':corners,'coverage':{'unrelated_clocks_unchanged':True,'explicit_exceptions_delays_unchanged':True,'explicit_exception_rows':len(exception_rows('78')),'core_clock_78':cl78[core],'core_clock_104':cl104[core],'scenario_errors':'empty','SDRAM_pin_registers':'PASS actual CI and local check','external_IO_signoff':'Not qualified: preserve known missing external SDRAM I/O delays/forwarded SDRAM_CLK and hard-IP clock warnings'},'manifest':{'provenance':'Successful actual in-job postcompile source manifest; 177 selected SHA256 values equal preflight, QSF differs only in tool-written edition metadata','source_count':len(manifest['compiled_source_sha256']),'sha256':sha(RAW/'output_files/resident-fit-manifest.json'),'QSF_normalization':qsf_normalization},'protected_checkout':'Production RTL/project/workflow bytes, HEAD, branch and index entries unchanged','raw_outputs':str(RAW.relative_to(ROOT)),'report_sha256':candidate['report_sha256']}
(ROOT/'docs/evidence/cache-probe-admission-retime-fit-inputs-20261116.json').write_text(json.dumps(manifest,indent=2)+'\n')
(ROOT/'docs/evidence/cache-probe-admission-retime-fit-20261116.json').write_text(json.dumps(evidence,indent=2)+'\n')
print('PASS actual input proof, both timing scenarios, exception/clock coverage and protected checkout')
