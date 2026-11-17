#!/usr/bin/env python3
"""Audit Step5L against hash-identical saved promoted-5K control evidence."""
import gzip,hashlib,json,re,subprocess
from collections import Counter
from pathlib import Path
from setup import ROOT,HERE,BASE

def sha(x):return hashlib.sha256(x).hexdigest()
def read(p):return p.read_text() if p.exists() else gzip.decompress(p.with_suffix(p.suffix+'.gz').read_bytes()).decode()
def load(p):return json.loads(p.read_text())
HEX={'p0pc','base','off','aa','p0a','p1a','p2a','opc','tlbpa','ptag','ramindex','pc','producer','data','result','flags','ipc','apc','shpc','p1pc','p2pc','cd'}
def events(s,prefix):return [dict((k,int(v,16 if k in HEX else 10)) for k,v in re.findall(r'(\w+)=(\w+)',l)) for l in s.splitlines() if l.startswith(prefix+' ')]
def main():
    out=ROOT/'build/sim/cpu-late-operand/step5l-03';control=ROOT/'build/sim/cpu-load-lookup/step5k-lookup-02'
    new=load(out/'result.json');old=load(control/'result.json');assert new['status']==old['status']=='PASS'
    assert new['programs']==old['programs'] and new['oracle']==old['oracle']
    m=new['manifest'];b=old['manifest'];assert m['image_id']==b['image_id']
    files=m['source']['files'];rtl={n:h for n,h in files.items() if n.startswith('rtl/') and Path(n).suffix in ['.v','.sv','.svh']}
    assert len(rtl)==60
    changed=[]
    for n,h in rtl.items():
        original=sha(subprocess.check_output(['git','show',BASE+':'+n],cwd=ROOT))
        assert original==b['source']['files'][n]
        if h!=original:changed.append(n)
        if (out/'source'/n).exists():assert sha((out/'source'/n).read_bytes())==h
    for name,h in m['fixtures'].items():assert sha((out/name).read_bytes())==h
    if (ROOT/m['executable']).exists():assert sha((ROOT/m['executable']).read_bytes())==m['executable_sha256']
    assert changed==['rtl/arm/zap_core.sv','rtl/arm/zap_issue_main.sv']
    dat=(ROOT/m['executable']).parent/'Vbench__verFiles.dat'
    compiler=out/'compiler-inputs.json'
    if dat.exists():
        names=set(re.findall(r'^S[^\n]*"/work/[^"\n]*/source/(rtl/[^"\n]+)"',dat.read_text(),re.M))
        compiler.write_text(json.dumps({n:rtl[n] for n in sorted(names)},indent=2)+'\n')
    assert len(load(compiler))==51
    comparisons=[];journals={};schedules={}
    for row in new['rows']:
        prev=next(x for x in old['rows'] if (x['case'],x['profile'])==(row['case'],row['profile']))
        comparisons.append(dict(case=row['case'],profile=row['profile'],old=prev['cycles'],new=row['cycles'],saved=prev['cycles']-row['cycles'],percent=100*(1-row['cycles']/prev['cycles'])))
        assert len(set(w['cycles'] for w in row['windows'][row['warmups']:]))==1
    for pattern in ['forward','reverse']:
        case='span-'+pattern;s=read(out/(case+'-0-0-0.log'));bs=read(control/(case+'-0-0-0.log'))
        journal={k:events(s,k) for k in ['LATE_ACCEPT','LATE_PICKUP','LATE_EXEC','PIPE_ISSUE','PIPE_RET','PIPE_EDGE']}
        bi=events(bs,'PIPE_ISSUE');br=events(bs,'PIPE_RET');ni=journal['PIPE_ISSUE'];nr=journal['PIPE_RET']
        assert [x['pc'] for x in ni]==[x['pc'] for x in bi]
        assert [x['pc'] for x in nr]==[x['pc'] for x in br]
        assert len(ni)==10241 and len(nr)==10239
        accepts=journal['LATE_ACCEPT'];pickups=journal['LATE_PICKUP']
        assert len(accepts)==len(pickups)==1534
        assert [(x['pc'],x['producer']) for x in accepts]==[(x['pc'],x['producer']) for x in pickups]
        assert all(y['t']-x['t']==2 for x,y in zip(accepts,pickups))
        for a,pick in zip(accepts,pickups):
            ex=next(x for x in journal['LATE_EXEC'] if x['pc']==a['pc'] and x['t']>=pick['t'])
            rt=next(x for x in nr if x['pc']==a['pc'] and x['t']>=pick['t'])
            assert ex['t']==pick['t']+2 and rt['t']==pick['t']+5
        measures={}
        for pc in [0x10093e3c,0x10093e5c,0x10093e80]:
            ai=[x['t'] for x in ni if x['pc']==pc];bl=[x['t'] for x in bi if x['pc']==pc-4][:512];al=[x['t'] for x in ni if x['pc']==pc-4][:512];oi=[x['t'] for x in bi if x['pc']==pc]
            assert len(ai)==len(oi)==len(al)==len(bl)==512
            distances=[a-l for a,l in zip(ai,al)];old_dist=[a-l for a,l in zip(oi,bl)]
            next_pc=pc+4
            bn=[x['t'] for x in bi if x['pc']==next_pc][:512];nn=[x['t'] for x in ni if x['pc']==next_pc][:512]
            bt=[x['t'] for x in br if x['pc']==pc][:512];nt=[x['t'] for x in nr if x['pc']==pc][:512]
            ex=[x['t'] for x in journal['LATE_EXEC'] if x['pc']==pc][:512]
            assert len(bn)==len(nn)==len(bt)==len(nt)==len(ex)==512
            downstream=dict(old_retire_from_load=dict(Counter(t-l for t,l in zip(bt,bl))),new_retire_from_load=dict(Counter(t-l for t,l in zip(nt,al))),old_next_issue_from_load=dict(Counter(t-l for t,l in zip(bn,bl))),new_next_issue_from_load=dict(Counter(t-l for t,l in zip(nn,al))),new_execute_from_load=dict(Counter(t-l for t,l in zip(ex,al))))
            measures[hex(pc)]=dict(downstream=downstream,accepts=sum(x['pc']==pc for x in accepts),old_issue_distance=dict(Counter(old_dist)),new_issue_distance=dict(Counter(distances)))
        # One representative accepted consumer and following useful instruction.
        a=accepts[0];p=pickups[0];idx=next(i for i,x in enumerate(ni) if x['pc']==a['pc'] and x['t']==a['t'])
        execute=next(x for x in journal['LATE_EXEC'] if x['pc']==a['pc'] and x['t']>p['t'])
        ret=next(x for x in nr if x['pc']==a['pc'] and x['t']>p['t'])
        old_start=next(x['t'] for x in bi if x['pc']==a['producer'])
        old_issue=next(x for x in bi if x['pc']==a['pc'])
        old_idx=bi.index(old_issue)
        old_exec=next(x for x in events(bs,'PIPE_EDGE') if x['apc']==a['pc'] and x['av'] and not x['stall'])
        old_ret=next(x for x in br if x['pc']==a['pc'])
        schedules[pattern]=dict(sites=measures,control_example=dict(load_issue=old_start,issue=old_issue,registered_execute=old_exec['t'],retire=old_ret,next_issue=bi[old_idx+1]),example=dict(accept=a,pickup=p,registered_execute=execute,retire=ret,next_issue=ni[idx+1]))
        journals[pattern]=journal
    safety=load(out/'safety.json');assert safety['status']=='PASS'
    safety_events={}
    for row in safety['rows']:
        profile=row['profile'].replace(':','-');text=read(out/f'safety-{profile}-0.log')
        accepts=events(text,'LATE_ACCEPT');executes=events(text,'LATE_EXEC');pickups=events(text,'LATE_PICKUP')
        killed=safety['symbols']['forbidden_fault_load'];cold=safety['symbols']['late_cold_consumer']
        assert any(x['pc']==killed for x in accepts)
        assert not any(x['pc']==killed for x in executes)
        ca=next(x for x in accepts if x['pc']==cold);cp=next(x for x in pickups if x['pc']==cold)
        assert not any(x['pc']==cold and x['t']<=cp['t'] for x in executes)
        safety_events[row['profile']]=dict(killed_accepted=True,killed_never_executes=True,cold_hold=cp['t']-ca['t'])
    response=load(ROOT/'build/sim/cpu-late-operand/step5l-response-01/result.json');assert response['status']=='PASS' and response['source']==m['source']
    diag=load(ROOT/'build/sim/cpu-late-operand/step5l-diagnostics-01/result.json');assert diag['status']=='PASS' and diag['source_id']==m['source']['source_id']
    jpeg=load(ROOT/'build/sim/jpeg-payload/step5l-jpeg-01/result.json');assert jpeg['status']=='PASS'
    jpegdir=ROOT/'build/sim/jpeg-payload/step5l-jpeg-01'
    executable=jpegdir/'obj/Vbench';jreceipt=jpegdir/'compiler-inputs.json'
    if executable.exists():
        dat=executable.parent/'Vbench__verFiles.dat'
        names=set(re.findall(r'^S[^\n]*"/work/[^"\n]*/source/(rtl/[^"\n]+)"',dat.read_text(),re.M))
        jreceipt.write_text(json.dumps(dict(executable_sha256=sha(executable.read_bytes()),inputs={n:rtl[n] for n in sorted(names)}),indent=2)+'\n')
    jpeg['compiler_inputs']=load(jreceipt)
    assert len(jpeg['compiler_inputs']['inputs'])==51
    assert all(jpeg['manifest']['source']['files'][n]==h for n,h in rtl.items())
    receipt=dict(status='PASS',decision='Retain isolated Step5L for broader qualification and timing; do not promote',control_commit=BASE,control_manifest=b,candidate_manifest=m,comparisons=comparisons,schedules=schedules,safety=safety,safety_events=safety_events,response_controls=response,diagnostics=diag,jpeg=jpeg,compiler_inputs=load(compiler),negatives=new['negatives'],rows=new['rows'])
    target=ROOT/'docs/evidence/cpu-late-operand-20261117.json'
    packed=gzip.compress(json.dumps(journals,separators=(',',':')).encode(),mtime=0);target.with_suffix('.events.json.gz').write_bytes(packed)
    receipt['events_sha256']=sha(packed);receipt['support_inputs']={str(p.relative_to(ROOT)):sha(p.read_bytes()) for p in [ROOT/'tests/cpu/cpu_load_lookup/bench.py',ROOT/'tests/cpu/cpu_load_pipeline/bench.py',ROOT/'tests/cpu/cpu_load_pipeline/safety.py',ROOT/'tests/cpu/cpu_store_postindex/diagnostics.py',ROOT/'tests/cpu/cache_probe_retime/jpeg_run.py']};receipt['driver_inputs']={str(p.relative_to(ROOT)):sha(p.read_bytes()) for p in HERE.glob('*.py')}
    target.write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n');print('PASS matched hashes, exact original work, registered pickup, useful execution and retirement')
if __name__=='__main__':main()
