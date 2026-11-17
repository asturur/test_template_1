#!/usr/bin/env python3
"""Read-only extraction of Quartus resource/timing summaries and retained hashes."""
from pathlib import Path
import argparse,json,re,hashlib,csv
p=argparse.ArgumentParser();p.add_argument('reports',type=Path);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
root=a.reports
read=lambda p: p.read_text(errors='replace')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
fit=read(root/'output_files/Template.fit.rpt')
summary=read(root/'output_files/Template.fit.summary')
sta=read(root/'output_files/Template.sta.summary')
resources={}
for key,label in [('ALMs','Logic utilization (in ALMs)'),('registers','Total registers'),('M10Ks','Total RAM Blocks'),('DSPs','Total DSP Blocks'),('block_memory_bits','Total block memory bits')]:
 m=re.search(re.escape(label)+r'\s*:\s*([\d,]+)',summary)
 resources[key]=int(m[1].replace(',','')) if m else None
for key,pattern in {
 'occupied_LABs':r'Total LABs:  partially or completely used\s*;\s*([\d,]+)',
 'MLABs':r'-- Memory LABs \(up to half of total LABs\)\s*;\s*([\d,]+)',
 'placed_ALMs':r'\[A\] ALMs used in final placement \[=a\+b\+c\+d\]\s*;\s*([\d,]+)',
 'routing_registers':r'-- Routing optimization registers\s*;\s*([\d,]+)',
 'design_registers':r'-- Design implementation registers\s*;\s*([\d,]+)',
}.items():
 m=re.search(pattern,fit);resources[key]=int(m[1].replace(',','')) if m else None
resources['physical_rows']=[s.strip() for s in fit.splitlines() if any(t in s.lower() for t in ['partially or completely used','memory alms','alms used in final placement','alms needed'])]
hierarchy=[];columns=None
for line in fit.splitlines():
 if not line.startswith(';'):continue
 fields=[f.strip() for f in line.split(';')[1:-1]]
 if 'Full Hierarchy Name' in fields and 'ALMs needed [=A-B+C]' in fields:columns=fields;continue
 if columns and len(fields)==len(columns):
  row=dict(zip(columns,fields))
  if row.get('Entity Name') in ['arm920_cache_access','arm920_cache_bank','arm920_cache_tags','arm920_cache_lines']:
   hierarchy.append(row)
timing=[]
for typ,slack,tns in re.findall(r'Type\s*:\s*(.*?)\nSlack\s*:\s*([\d.\-]+)\nTNS\s*:\s*([\d.\-]+)',sta):timing.append({'type':typ,'slack_ns':float(slack),'TNS_ns':float(tns)})
def first_path(path):
 text=read(path)
 chunks=re.split(r'(?=Path #\d+:)',text)
 if len(chunks)<2:return {'no_paths':True,'intro':text[:250]}
 chunk=chunks[1];row={};data=False
 for line in chunk.splitlines():
  if not line.startswith(';'):continue
  f=[v.strip() for v in line.split(';')[1:-1]]
  if not f:continue
  if f[0] in ['From Node','To Node','Slack','Data Delay','Launch Clock','Latch Clock'] and len(f)>1:row[f[0]]=f[1]
  if f[0]=='Number of Logic Levels':row['logic_levels']=next((v for v in f[1:] if v),'')
  if f[0]=='Data':data=True
  if f[0]=='Required Path':data=False
  if data and f[0] in ['Cell','Routing Element','IC'] and len(f)>3:row['data_'+f[0]]=f[3]
 return row
result={'hierarchy' :hierarchy,'resources':resources,'normal_timing':timing,'global_worst_path':first_path(root/'output_files/timing/worst-setup-full.rpt') if (root/'output_files/timing/worst-setup-full.rpt').exists() else None,'report_sha256':{str(p.relative_to(root)):sha(p) for p in root.rglob('*') if p.is_file() and p.suffix in ['.rpt','.summary','.json','.csv','.log','.txt','.tcl']}}
timingroot=root/'output_files/timing/resident-store'
if timingroot.exists():
 result['scenario_errors']=read(timingroot/'errors.txt') if (timingroot/'errors.txt').exists() else 'MISSING'
 result['scenarios']={}
 for freq in ['78','104']:
  d=timingroot/freq;r={'coverage_files':{p.name:read(p) for p in d.glob('clock-coverage*')}}
  corners=[]
  for c in sorted(d.glob('corner-*')):
   row={'directory':str(c.relative_to(root)),'condition':read(c/'operating-condition.txt')}
   for kind in ['setup','hold','recovery','removal']:
    f=c/(kind+'-summary.rpt');row[kind]=read(f) if f.exists() else 'MISSING'
   row['first_paths']={p.name:first_path(p) for p in c.glob('*.rpt') if p.name in ['setup.rpt','pipeline_to_probe.rpt','any_to_pipeline.rpt','certificate_to_owner.rpt','dirty_forwarding.rpt','reset_to_probe.rpt','any_to_probe.rpt','pipeline_to_any.rpt']}
   row['groups']=read(c/'groups.txt') if (c/'groups.txt').exists() else 'MISSING'
   corners.append(row)
  r['corners']=corners;result['scenarios'][freq]=r
if (root/'output_files/resident-fit-manifest.json').exists():result['source']=json.loads(read(root/'output_files/resident-fit-manifest.json'))
a.output.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(resources,indent=2));print('normal core setup',[r for r in timing if r['type'].startswith('Setup') and 'emu|pll|' in r['type']])
