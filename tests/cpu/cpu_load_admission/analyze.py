#!/usr/bin/env python3
"""Compare one permission-register experiment directly to exact retained 5L."""
import gzip,json,re,hashlib,subprocess
from collections import Counter
from pathlib import Path
from setup import ROOT,HERE,BASE

def sha(raw):return hashlib.sha256(raw).hexdigest()
def load(p):return json.loads(p.read_text())
def read(p):return p.read_text() if p.exists() else gzip.decompress(p.with_suffix(p.suffix+'.gz').read_bytes()).decode()
HEX={'pc','producer','data','result','flags','ipc','apc','p0pc','shpc','p1pc','p2pc','cd','base','off','aa','p0a','p1a','p2a','opc','tlbpa','ptag','ramindex','va','pa'}
def events(s,prefix):return [dict((k,int(v,16 if k in HEX else 10)) for k,v in re.findall(r'(\w+)=(\w+)',l)) for l in s.splitlines() if l.startswith(prefix+' ')]
def main():
    out=ROOT/'build/sim/cpu-load-admission/step5m-04';baseline=ROOT/'build/sim/cpu-late-operand/step5l-03'
    n=load(out/'result.json');b=load(baseline/'result.json');assert n['status']==b['status']=='PASS'
    assert n['programs']==b['programs'] and n['oracle']==b['oracle']
    nm=n['manifest'];bm=b['manifest'];assert nm['image_id']==bm['image_id']
    rtl={k:v for k,v in nm['source']['files'].items() if k.startswith('rtl/') and Path(k).suffix in ['.v','.sv','.svh']};assert len(rtl)==60
    changed=[k for k in rtl if rtl[k]!=bm['source']['files'][k]]
    assert changed==['rtl/arm/zap_core.sv','rtl/arm/zap_cp15_cb.sv','rtl/arm/zap_dcache.sv','rtl/arm/zap_top.sv']
    for k,h in rtl.items():
        if (out/'source'/k).exists():assert sha((out/'source'/k).read_bytes())==h
    if (out/'source').exists():
        dc=(out/'source/rtl/arm/zap_dcache.sv').read_text()
        admitted=dc.split('wire admitted =',1)[1].split(';',1)[0]
        assert not any(x in admitted for x in ['i_baddr','i_dac_reg','i_sr','i_mmu_en','tlb_busy','checked_owner'])
        instance=dc.split(') cache_adapter (',1)[1].split('  logic tlb_raw_stb',1)[0]
        assert not any(x in instance for x in ['tlb_phy_addr','tlb_fault','tlb_cacheable','tlb_busy)','pending_translation ?','translation_wait(translation_wait)'])
    dat=out/'obj/Vbench__verFiles.dat';compiler=out/'compiler-inputs.json'
    if dat.exists():
        names=set(re.findall(r'^S[^\n]*"/work/[^"\n]*/source/(rtl/[^"\n]+)"',dat.read_text(),re.M));compiler.write_text(json.dumps({k:rtl[k] for k in sorted(names)},indent=2)+'\n')
    assert len(load(compiler))==51
    comparisons=[];journals={};streams={};accounting={};examples={}
    for row in n['rows']:
        old=next(x for x in b['rows'] if (x['case'],x['profile'])==(row['case'],row['profile']))
        comparisons.append(dict(case=row['case'],profile=row['profile'],five_l=old['cycles'],five_m=row['cycles'],added=row['cycles']-old['cycles'],percent_added=100*(row['cycles']/old['cycles']-1)))
        assert len({w['cycles'] for w in row['windows'][row['warmups']:]})==1
        if row['profile']!='0:0':continue
        case=row['case'];ns=read(out/f'{case}-0-0-0.log');bs=read(baseline/f'{case}-0-0-0.log')
        new={k:events(ns,k) for k in ['PIPE_ISSUE','PIPE_RET','PIPE_EDGE','ADMISSION_EDGE','LATE_ACCEPT','LATE_PICKUP']}
        old={k:events(bs,k) for k in ['PIPE_ISSUE','PIPE_RET','PIPE_EDGE']}
        assert [x['pc'] for x in new['PIPE_RET']]==[x['pc'] for x in old['PIPE_RET']]
        if case in ['stream','multiline']:
            values={}
            for label,j in [('5L',old),('5M',new)]:
                starts=[x for x in j['PIPE_ISSUE'] if 0x10000008<=x['pc']<=0x10000404]
                assert len(starts)==256;steady=starts[16:-16]
                values[label]=dict(starts=224,elapsed=steady[-1]['t']-steady[0]['t']+1,gaps=dict(Counter(y['t']-x['t'] for x,y in zip(steady,steady[1:]))))
            streams[case]=values
        if case.startswith('span-'):
            neww=row['windows'][2];oldw=old_row=next(x for x in b['rows'] if x['case']==case and x['profile']=='0:0')['windows'][2]
            accounting[case]={k:dict(five_l=oldw[k],five_m=neww[k],delta=neww[k]-oldw[k]) for k in ['read_stall','write_stall','load_lock','shift_lock','empty','other','cycles']}
            assert sum(accounting[case][k]['delta'] for k in ['read_stall','write_stall','load_lock','shift_lock','empty','other'])==neww['cycles']-oldw['cycles']
            examples[case]={}
            for pc in [0x10093e38,0x10093e60,0x10093e64,0x10093e6c,0x10093e70]:
                vals={}
                for label,j in [('5L',old),('5M',new)]:
                    edges=j['PIPE_EDGE'];start=next(x['t'] for x in edges if x['pop'] and x['ipc']==pc)
                    offer=next(x['t'] for x in edges if x['offer'] and x['opc']==pc)
                    ack=next(x['t'] for x in edges if x['offer'] and x['ack'] and x['opc']==pc)
                    vals[label]=dict(issue=start,first_offer=offer-start,ack=ack-start)
                examples[case][hex(pc)]=vals
        journals[case]=dict(candidate=new,control=old)
    assert streams['stream']['5L']['elapsed']==224 and streams['stream']['5M']['elapsed']==336
    safety=load(out/'safety.json');assert safety['status']=='PASS'
    context=load(ROOT/'build/sim/cpu-load-admission/step5m-context-03/result.json');assert context['status']=='PASS' and context['source']==nm['source']
    diagnostics=load(ROOT/'build/sim/cpu-load-admission/step5m-diagnostics-01/result.json');assert diagnostics['status']=='PASS' and diagnostics['source_id']==nm['source']['source_id']
    response=load(ROOT/'build/sim/cpu-load-admission/step5m-response-01/result.json');assert response['status']=='PASS' and response['source']==nm['source']
    # Cache collision/revocation machinery is byte-identical; reuse its two-run
    # poisoned-RAM pressure receipt, without relabeling it a new full-CPU run.
    guard=load(ROOT/'build/sim/cpu-load-lookup/step5k-pressure-01/result.json');assert guard['status']=='PASS'
    for f,h in guard['source'].items():
        name=Path(f).name
        if name=='ngage_bram.v' or name=='test.v':continue
        if 'source/' in f and name.endswith('.sv'):assert rtl['rtl/arm920/'+name]==h
    receipt=dict(status='PASS',decision='Reject current 5M overlay; keep 5L. Registered demand permission cuts the identified live cone but fails measured throughput and span costs.',path=load(ROOT/'docs/evidence/cpu-load-admission-path-20261117.json'),candidate_manifest=nm,baseline_manifest=bm,comparisons=comparisons,streams=streams,accounting=accounting,examples=examples,safety=safety,context_negatives=context,diagnostics=diagnostics,response_controls=response,reused_cache_guards=guard,compiler_inputs=load(compiler),rows=n['rows'],negatives=n['negatives'],source_level_extra_state_bits=165,fit_performed=False,source_combinational_cut_audited=True)
    target=ROOT/'docs/evidence/cpu-load-admission-20261117.json';packed=gzip.compress(json.dumps(journals,separators=(',',':')).encode(),mtime=0);target.with_suffix('.events.json.gz').write_bytes(packed)
    receipt['events_sha256']=sha(packed);receipt['driver_inputs']={str(p.relative_to(ROOT)):sha(p.read_bytes()) for p in HERE.iterdir() if p.suffix in ['.py','.sv']}
    target.write_text(json.dumps(receipt,indent=2)+'\n');print('PASS measured rejection: exact 5L work, context negatives, source cut, safety and stream/span costs')
if __name__=='__main__':main()
