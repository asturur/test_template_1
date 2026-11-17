#!/usr/bin/env python3
"""Validate final artifacts and emit a small, media-free comparison receipt."""
import argparse,collections,hashlib,json,math,re,statistics,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
p=argparse.ArgumentParser();p.add_argument('--control',type=Path,required=True);p.add_argument('--donor',type=Path,required=True);p.add_argument('--qualification',type=Path,required=True);p.add_argument('--jpeg-control',type=Path);p.add_argument('--jpeg-donor',type=Path);p.add_argument('--drain-control',type=Path);p.add_argument('--drain-donor',type=Path);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
sha=lambda x:hashlib.sha256(x).hexdigest()
def read(p):return json.loads(p.read_text())
def sequence(text):
 return [(int(re.search(r'c=(\d+)',l)[1]),int(l.split('pc=')[1],16)) for l in text.splitlines() if l.startswith('TRACE_RET ')]
def parsed(text,prefix):return [{k:int(v) for k,v in re.findall(r'(\w+)=(-?\d+)',l)} for l in text.splitlines() if l.startswith(prefix+' ')]
old,new=read(a.control/'result.json'),read(a.donor/'result.json');qual=read(a.qualification/'result.json');assert old['status']==new['status']==qual['status']=='PASS'
assert qual['executable_sha256']==new['manifest']['executable_sha256']
for field in ['image_id','payload_sha256','original_rom_sha256','programs','normal_import_link']:
 assert old['manifest'][field]==new['manifest'][field],field
# Verify every compiled5C source against the requested immutable commit and
# against the previously accepted original matrix/transpose executable inputs.
source=a.control/'source';names=['rtl/ngage_cpu.sv','rtl/ngage_bram.v']
for d in ['rtl/arm','rtl/arm920']:names+=sorted(str(f.relative_to(source)) for f in (source/d).iterdir() if f.suffix in ['.v','.sv'])
accepted=read(ROOT/'build/sim/spmark-payload/product-candidate-final-02/manifest.json')
compiled={}
for n in names:
 raw=(source/n).read_bytes();h=sha(raw);compiled[n]=h
 assert h==sha(subprocess.check_output(['git','show','78d53d4:'+n],cwd=ROOT)),n
 assert h==accepted['source']['files'][n],n
includes={}
for f in (source/'rtl').rglob('*.svh'):
 n=str(f.relative_to(source));h=sha(f.read_bytes())
 assert h==sha(subprocess.check_output(['git','show','78d53d4:'+n],cwd=ROOT))
 assert h==accepted['source']['files'][n]
 includes[n]=h
rows=[];traces={};base={(r['case'],r['profile']):r for r in old['rows']}
assert len(base)==len(new['rows'])==12
for nr in new['rows']:
 key=nr['case'],nr['profile'];cr=base[key];assert cr['oracle']==nr['oracle'];assert cr['program_sha256']==nr['program_sha256']
 paths=[d/f'{key[0]}-{key[1].replace(":","-")}-0.log' for d in [a.control,a.donor]]
 texts=[f.read_text() for f in paths];seqs=list(map(sequence,texts));assert [pc for c,pc in seqs[0]]==[pc for c,pc in seqs[1]],key
 traffic=[parsed(t,'TRAFFIC') for t in texts];assert all(len(t)==7 for t in traffic)
 row=dict(case=key[0],profile=key[1],operations=cr['operations'],unit=cr['unit'],program_sha256=cr['program_sha256'],checks=nr['oracle']['outputs'],status='PASS',retirement_pc_sequence_count=len(seqs[0]),retirement_pc_sequence_sha256=sha(json.dumps([pc for c,pc in seqs[0]]).encode()))
 for tag,r,t in zip(['5c','ngage2'],[cr,nr],traffic):
  row[tag]=dict(cycles=r['body_cycles_median'],cycles_per_operation=r['cycles_per_operation'],windows=r['windows'],traffic=t,deterministic_repeats=r['deterministic_repeats'],payload_windows=r['payload_windows'])
 row['throughput_5c_cycles_over_ngage2_cycles']=cr['body_cycles_median']/nr['body_cycles_median'];rows.append(row)
 if key[1]=='0:0':traces[key[0]]=seqs
# Bounded trace summaries: retirement intervals, never isolated additive savings.
def interval(seq,lo,hi,limit=40):
 vals=[]
 for i,(c,pc) in enumerate(seq):
  if pc==lo:
   for cc,pp in seq[i+1:i+limit]:
    if pp==hi:vals.append(cc-c);break
 return dict(count=len(vals),median=statistics.median(vals),min=min(vals),max=max(vals)) if vals else None
schedules={}
for case,pairs in [('matrix4',[(0x100011c4,0x100011c8),(0x100011c8,0x100011cc),(0x10002184,0x100011c4),(0x100011e4,0x10002188)]),('transpose4',[(0x10002644,0x10002650),(0x10002650,0x10002654),(0x100026a4,0xcc),(0x10002644,0x100026a4)])]:
 schedules[case]={f'{lo:08x}->{hi:08x}':{tag:interval(seq,lo,hi,limit=2 if case=='matrix4' and lo==0x100011e4 else 40) for tag,seq in zip(['5c','ngage2'],traces[case])} for lo,hi in pairs}
result=dict(status='PASS',reference_commit=old['manifest']['source']['commit'],donor_revision=new['manifest']['source']['commit'],memory_contract='read-fill16-per-clock, scalar32-per-word-wait-v1; donor burst writes use scalar32 rule per word',compiled_5c_inputs=compiled,compiled_5c_includes=includes,donor_selected_inputs={n:new['manifest']['source']['dependencies'][n] for n in ['rtl/cpu/arm925t_gen.v','sim/stubs/altsyncram.sv','sim/stubs/altdpram.sv']},artifacts={k:str(v) for k,v in [('control',a.control),('donor',a.donor),('qualification',a.qualification)]},manifest_sha256={'5c':sha((a.control/'manifest.json').read_bytes()),'ngage2':sha((a.donor/'manifest.json').read_bytes())},rows=rows,schedules=schedules,observer_qualification=qual,geometric_throughput_ratio_by_profile={p:math.exp(statistics.mean(math.log(r['throughput_5c_cycles_over_ngage2_cycles']) for r in rows if r['profile']==p)) for p in ['0:0','2:9']})
if a.jpeg_control and a.jpeg_donor:
 jc,jd=read(a.jpeg_control/'result.json'),read(a.jpeg_donor/'result.json')
 assert jc['status']==jd['status']=='PASS' and jc['wrong_output_rejected'] and jd['wrong_output_rejected']
 assert jc['manifest']['programs']==jd['manifest']['programs']
 result['jpeg']=dict(control_artifact=str(a.jpeg_control),donor_artifact=str(a.jpeg_donor),meaning='Separate original Thumb 8x8 JPEG error-diffusion block; excluded from six-case index',rows=[])
 for cr,nr in zip(jc['rows'],jd['rows']):
  assert cr['profile']==nr['profile']
  result['jpeg']['rows'].append(dict(profile=cr['profile'],reference=cr,donor=nr,throughput_ratio=cr['body_cycles_median']/nr['body_cycles_median']))
 result['jpeg']['thumb_bl_suffixes']=jd['manifest']['oracle']['thumb_bl_suffixes']
if a.drain_control and a.drain_donor:
 result['passive_drain']={}
 for tag,d in [('5c',a.drain_control),('ngage2',a.drain_donor)]:
  dr=read(d/'result.json');assert dr['status']=='PASS'
  row=dr['rows'][0];original=next(r for r in rows if r['case']==row['case'] and r['profile']==row['profile'])
  assert row['windows']==original[tag]['windows'],'drain instrumentation changed original window'
  t=(d/'fill16_frame-2-9-0.log').read_text();drains=parsed(t,'DRAIN');assert len(drains)==7
  assert parsed((d/'fill16_frame-2-9-1.log').read_text(),'DRAIN')==drains
  result['passive_drain'][tag]=dict(artifact=str(d),windows=drains,scored_body_plus_first_empty_cycles=[w['cycles']+de['extra_cycles'] for w,de in zip(row['windows'][2:],drains[2:])])
# Additional inspectable interval evidence.
result['bulk_store_examples']={}
for case,pc in [('fill16_tail',0x10002ae4),('fill8_tail',0x10002a3c)]:
 result['bulk_store_examples'][case]={}
 for tag,seq in zip(['5c','ngage2'],traces[case]):
  ix=next(i for i,(c,p) in enumerate(seq) if p==pc)
  result['bulk_store_examples'][case][tag]=[dict(pc=hex(p),relative_cycle=c-seq[ix][0]) for c,p in seq[ix:ix+10]]
result['all_matrix_call_return_intervals']={}
for tag,seq in zip(['5c','ngage2'],traces['matrix4']):
 calls=[];returns=[]
 for (c,p),(cc,pp) in zip(seq,seq[1:]):
  if 0x1000216c<=p<0x10002644 and pp==0x100011c4:calls.append(cc-c)
  if p==0x100011e4 and 0x1000216c<=pp<0x10002644:returns.append(cc-c)
 assert len(calls)==len(returns)==1024
 result['all_matrix_call_return_intervals'][tag]={k:dict(count=len(v),median=statistics.median(v),min=min(v),max=max(v)) for k,v in [('calls',calls),('returns',returns)]}
# Independently regenerate each original unrolled helper product. The actual
# function orders row, column, k, storing into column-major output. W is not
# a complete register journal: background load RF writes use another port.
import struct,sys
sys.path.insert(0,str(ROOT/'tests/cpu/spmark_payload'))
from workloads import cases
case=cases()[0];aa=struct.unpack('<256i',case['writes'][0][1]);bb=struct.unpack('<256i',case['writes'][1][1])
expected_products=[aa[m*16+r+k*4]*bb[m*16+k+c*4] for m in range(16) for r in range(4) for c in range(4) for k in range(4)]
products=[]
for l in (a.donor/'matrix4-0-0-0.log').read_text().splitlines():
 if not l.startswith('TRACE_W '):continue
 f=dict(re.findall(r'(\w+)=([0-9a-f]+)',l))
 if int(f['pc'],16)!=0x100011c8:continue
 assert int(f['pair'])==1 and int(f['tag0'])==2 and int(f['tag1'])==3
 products.append((int(f['data1'],16)<<32)|int(f['data0'],16))
assert products==[x&((1<<64)-1) for x in expected_products]
result['donor_checked_paired_smull_products']=len(products)
result['paired_product_oracle']='Original unrolled row/column/k load offsets and identical signed input words; all actual paired R2/R3 data match'
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,sort_keys=True,indent=2)+'\n')
for r in rows:print(r['case'],r['profile'],r['5c']['cycles'],r['ngage2']['cycles'],round(r['throughput_5c_cycles_over_ngage2_cycles'],4))
print('geometric',result['geometric_throughput_ratio_by_profile'])
