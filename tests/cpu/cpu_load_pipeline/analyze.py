#!/usr/bin/env python3
"""Audit matched 5J runs and preserve instruction/owner schedules, not game code."""
import argparse,gzip,hashlib,json,re,subprocess
from collections import Counter
from pathlib import Path
from setup import ROOT,BASE

def sha(raw):return hashlib.sha256(raw).hexdigest()
def load(p):return json.loads(p.read_text())
def log(p):return p.read_text() if p.exists() else gzip.decompress(p.with_suffix('.log.gz').read_bytes()).decode()
def events(text,prefix):
    hexkeys={'pc','ipc','base','off','shpc','apc','aa','p0pc','p0a','p1pc','p1a','p2pc','p2a','opc','cd','tlbpa','ptag','ramindex'}
    return [dict((k,int(v,16 if k in hexkeys else 10)) for k,v in re.findall(r'(\w+)=(\w+)',l)) for l in text.splitlines() if l.startswith(prefix+' ')]
def rtl(m):return {n:h for n,h in m['source']['files'].items() if n.startswith('rtl/') and Path(n).suffix in ['.v','.sv','.svh']}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--control',default='step5j-control-04');p.add_argument('--candidate',default='step5j-candidate-02')
    a=p.parse_args();runs={k:ROOT/'build/sim/cpu-load-pipeline'/v for k,v in vars(a).items()}
    result={k:load(v/'result.json') for k,v in runs.items()}
    assert all(r['status']=='PASS' for r in result.values())
    manifest={k:r['manifest'] for k,r in result.items()}
    assert result['control']['programs']==result['candidate']['programs']
    assert result['control']['oracle']==result['candidate']['oracle']
    assert manifest['control']['image_id']==manifest['candidate']['image_id']
    assert manifest['control']['fixtures']==manifest['candidate']['fixtures']
    rr={k:rtl(m) for k,m in manifest.items()};assert all(len(x)==60 for x in rr.values())
    differences=[n for n in rr['control'] if rr['control'][n]!=rr['candidate'][n]]
    assert differences==['rtl/arm/zap_core.sv']
    for n,h in rr['control'].items():
        assert sha((ROOT/n).read_bytes())==h
        assert sha(subprocess.check_output(['git','show',BASE+':'+n],cwd=ROOT))==h
    assert sha((Path(__file__).parent/'rtl/arm/zap_core.sv').read_bytes())==rr['candidate']['rtl/arm/zap_core.sv']
    receipt=dict(status='PASS',production='Retain exact 5F; isolated research prototype only',
                 changed_rtl=differences,manifests=manifest,variants={},comparisons=[],trace_summary={})
    journal={}
    for label,directory in runs.items():
        r=result[label];m=manifest[label]
        for n,h in m['fixtures'].items():assert sha((directory/n).read_bytes())==h
        exe=ROOT/m['executable']
        if exe.exists():assert sha(exe.read_bytes())==m['executable_sha256']
        for payload in ['span','transpose','stream','dependency']:
            f=directory/(payload+'-payload.hex')
            if f.exists():
                other=runs['candidate' if label=='control' else 'control']/(payload+'-payload.hex')
                assert sha(f.read_bytes())==sha(other.read_bytes())
        pipe={};traces={}
        for row in r['rows']:
            case=row['case'];profile=row['profile'];iw,dw=profile.split(':')
            text=log(directory/f'{case}-{iw}-{dw}-0.log')
            ps=events(text,'PIPE_WINDOW');assert len(ps)==len(row['windows'])
            pipe[case+' '+profile]=ps
            for w in row['windows'][row['warmups']:]:assert w['reads']==w['writes']==w['lines']==0
            if profile=='0:0':
                traces[case]={typ:events(text,typ) for typ in ['PIPE_EDGE','PIPE_ISSUE','PIPE_RET']}
        journal[label]=traces
        # Exactly 256 ordinary architectural starts and retirements in the
        # predeclared stream region; exclude STM/LDM macro-uops and its tail.
        stream=traces['stream'];lo,hi=0x10000008,0x10000408
        iss=[e for e in stream['PIPE_ISSUE'] if lo<=e['pc']<hi]
        ret=[e for e in stream['PIPE_RET'] if lo<=e['pc']<hi]
        expected=list(range(lo,hi,4));assert [e['pc'] for e in iss]==[e['pc'] for e in ret]==expected
        assert all(e['last']==1 for e in iss)
        steady=iss[16:240];gaps=Counter(b['t']-a['t'] for a,b in zip(steady,steady[1:]))
        elapsed=steady[-1]['t']-steady[0]['t']+1
        retired_steady=ret[16:240]
        retired_elapsed=retired_steady[-1]['t']-retired_steady[0]['t']+1
        retired_gaps=Counter(b['t']-a['t'] for a,b in zip(retired_steady,retired_steady[1:]))
        assert retired_elapsed==(224 if label=='candidate' else 446)
        checked=[]
        for e in stream['PIPE_EDGE']:
            pc=e['p2pc']
            if e['comp'] and lo<=pc<hi and (pc-lo)%8==0:
                index=(pc-lo)//8
                assert e['cf']==0 and e['cd']==0x100+index%8
                checked.append(pc)
        assert len(checked)==len(set(checked))==128
        dependencies=[]
        edges=traces['span-forward']['PIPE_EDGE']
        starts=[e['t'] for e in traces['span-forward']['PIPE_ISSUE'] if e['pc']==0x10093e38]
        for pc in [0x10093e38,0x10093e58,0x10093e7c]:
            start=next(e['t'] for e in edges if e['t']>=starts[7] and e['pop'] and e['ipc']==pc)
            end=next(e['t'] for e in edges if e['t']>start and e['pop'] and e['ipc']==pc+4)
            seq=[dict(e,t=e['t']-start) for e in edges if start<=e['t']<=end]
            dependencies.append(dict(pc=hex(pc),consumer=hex(pc+4),load_use=end-start,edges=seq))
        # The accepted original retirement streams cannot change with the
        # request stage. The last span branch is checked by span.vh itself.
        for case in ['span-forward','span-reverse','transpose4']:
            pcs=[e['pc'] for e in traces[case]['PIPE_RET'] if 0x10000000<=e['pc']<0x10100000]
            other=result['candidate' if label=='control' else 'control']
            if case=='transpose4':assert len(pcs)==800
            else:assert pcs==[0x10093e38+4*(i%20) for i in range(10239)]
        safety=load(directory/'safety.json');assert safety['status']=='PASS'
        receipt['variants'][label]=dict(rows=r['rows'],oracles=r['oracle'],negatives=r['negatives'],
                                        pipeline_windows=pipe,safety=safety)
        receipt['trace_summary'][label]=dict(stream_starts=len(iss),stream_retirements=len(ret),
                                            stream_region_elapsed=iss[-1]['t']-iss[0]['t']+1,
                                            steady_starts=len(steady),steady_elapsed=elapsed,
                                            steady_retired_elapsed=retired_elapsed,steady_retirement_gaps=dict(retired_gaps),
                                            steady_start_gaps=dict(gaps),checked_load_completions=len(checked),
                                            span_dependencies=dependencies)
        compiler=directory/'compiler-inputs.json'
        dat=directory/'obj/Vbench__verFiles.dat'
        if dat.exists():
            names=set(re.findall(r'^S[^\n]*"/work/[^"\n]*/source/(rtl/[^"\n]+)"',dat.read_text(),re.M))
            compiler.write_text(json.dumps({n:rr[label][n] for n in sorted(names)},indent=2)+'\n')
        assert len(load(compiler))==51
    for case in ['span-forward','span-reverse','transpose4']:
        assert [e['pc'] for e in journal['control'][case]['PIPE_RET']]==[e['pc'] for e in journal['candidate'][case]['PIPE_RET']]
    crows={(r['case'],r['profile']):r for r in result['control']['rows']}
    for row in result['candidate']['rows']:
        old=crows[row['case'],row['profile']]
        receipt['comparisons'].append(dict(case=row['case'],profile=row['profile'],
                                            control=old['cycles'],candidate=row['cycles'],
                                            cycles_saved=old['cycles']-row['cycles'],
                                            relative_reduction=1-row['cycles']/old['cycles']))
    legacy={k:load(ROOT/'build/sim/cpu-load-pipeline'/v/'result.json') for k,v in [('control','step5j-control-03'),('candidate','step5j-candidate-01')]}
    assert all(r['status']=='PASS' for r in legacy.values())
    for label,r in legacy.items():assert rtl(r['manifest'])==rr[label]
    assert legacy['control']['programs']==legacy['candidate']['programs']
    receipt['legacy_transpose_layout']={k:[r for r in v['rows'] if r['case']=='transpose4'] for k,v in legacy.items()}
    diag=load(ROOT/'build/sim/cpu-load-pipeline/step5j-diagnostics-01/result.json');assert diag['status']=='PASS'
    assert diag['source_id']==manifest['candidate']['source']['source_id']
    receipt['diagnostics']=diag
    out=ROOT/'docs/evidence/cpu-load-pipeline-20261117.json'
    compressed=gzip.compress(json.dumps(journal,separators=(',',':')).encode(),mtime=0)
    out.with_suffix('.events.json.gz').write_bytes(compressed)
    receipt['events_sha256']=sha(compressed);receipt['analyzer_sha256']=sha(Path(__file__).read_bytes())
    out.write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    print('PASS matched inputs, production control, one overlay, retirement streams, RAM mutations, useful starts and safety')
    print('steady',receipt['trace_summary']['control']['steady_starts'],'starts:',receipt['trace_summary']['control']['steady_elapsed'],'->',receipt['trace_summary']['candidate']['steady_elapsed'],'clocks')

if __name__=='__main__':main()
