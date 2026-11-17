#!/usr/bin/env python3
"""Collect Stop 3D paths and coverage without changing RTL or fitting again."""
from pathlib import Path
import argparse, hashlib, json, re, subprocess

ROOT = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser()
p.add_argument('reports', type=Path)
p.add_argument('--output', required=True, type=Path)
a = p.parse_args()
subprocess.run(['python3', str(ROOT/'tools/resident_store_fit/collect.py'), str(a.reports), '--output', str(a.output)], check=True)
result = json.loads(a.output.read_text())
read = lambda p: p.read_text(errors='replace')

def cells(text):
    return [[v.strip() for v in line.split(';')[1:-1]] for line in text.splitlines() if line.startswith(';')]

def paths(text):
    rows = []
    for chunk in re.split(r'(?=Path #\d+:)', text)[1:]:
        row = {}; data = False
        for f in cells(chunk):
            if not f: continue
            if f[0] in ['From Node','To Node','Slack','Data Delay','Launch Clock','Latch Clock'] and len(f)>1:
                row[f[0]] = f[1]
            if f[0]=='Number of Logic Levels': row['logic_levels'] = next((v for v in f[1:] if v),'')
            if f[0]=='Data': data=True
            if f[0]=='Required Path': data=False
            if data and f[0] in ['Cell','Routing Element','IC'] and len(f)>3: row['data_'+f[0]]=f[3]
        # Named combinational hops are evidence of surviving control routes.
        row['control_hops'] = {name:sorted(set(re.findall(r'[^;\n]*'+re.escape(name)+r'[^;\n]*', chunk))) for name in ['u_data_completion','fast_hit','pipe_busy','probe_read','reset_drain'] if name in chunk}
        rows.append(row)
    return rows

fit = read(a.reports/'output_files/Template.fit.rpt')
hierarchy=[]; columns=None
for f in cells(fit):
    if 'Full Hierarchy Name' in f and 'ALMs needed [=A-B+C]' in f: columns=f; continue
    if columns and len(f)==len(columns):
        row=dict(zip(columns,f))
        if row.get('Entity Name') in ['ngage_cpu','zap_top','zap_core','zap_dcache','zap_cache','arm920_cache_adapter','arm920_cache_access','arm920_cache_bank','arm920_cache_tags','arm920_cache_lines','arm920_tlb','arm920_tlb_bank']:
            hierarchy.append(row)
result['cpu_hierarchy'] = hierarchy
root=a.reports/'output_files/timing/resident-store'
corners=[]
for freq in ['78','104']:
    for d in sorted((root/freq).glob('corner-*')):
        row={'MHz':int(freq),'directory':str(d.relative_to(a.reports)),'condition':read(d/'operating-condition.txt')}
        for kind in ['setup','hold','recovery','removal','min-pulse']:
            text=read(d/(kind+'.rpt'))
            match=re.search(r'Worst case slack is ([\d.\-]+)',text)
            row[kind]=float(match[1]) if match else None
        row['checks']={f[0]:int(f[1]) for f in cells(read(d/'check-timing.rpt')) if len(f)==2 and f[1].isdigit()}
        row['UCP']={f[0]:int(f[1]) for f in cells(read(d/'unconstrained.rpt')) if len(f)==3 and f[1].isdigit()}
        row['groups']={}
        for line in read(d/'groups.txt').splitlines():
            name, value=line.split(': ',1)
            text=read(d/(name+'.rpt'))
            inventory=read(d/(name+'-keepers.txt'))
            row['groups'][name]={'report_result':value,'reported_paths':paths(text),'matched_keepers':{side:int(n) for side,n in re.findall(r'(from|to) matched_keepers=(\d+)',inventory)},'resolved_keepers_sha256':hashlib.sha256((d/(name+'-keepers.txt')).read_bytes()).hexdigest()}
        row['global_paths']=paths(read(d/'setup.rpt'))
        row['recovery_paths']=paths(read(d/'recovery.rpt'))
        corners.append(row)
result['detailed_corners']=corners
a.output.write_text(json.dumps(result,indent=2)+'\n')
print('Collected',len(corners),'corners with resolved group inventories and physical path details')
