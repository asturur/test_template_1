#!/usr/bin/env python3
"""Audit three matched CPUs, useful dependent advancement and actual stores."""
import argparse,gzip,hashlib,json,re,subprocess
from collections import Counter
from pathlib import Path
from setup import ROOT,HERE,BASE

def sha(raw):return hashlib.sha256(raw).hexdigest()
def load(p):return json.loads(p.read_text())
def log(p):return p.read_text() if p.exists() else gzip.decompress(p.with_suffix('.log.gz').read_bytes()).decode()
HEX={'pc','ipc','base','off','shpc','apc','aa','p0pc','p0a','p1pc','p1a','p2pc','p2a','opc','cd','tlbpa','ptag','ramindex',
     'hpc','ha','pa','p1tag','p2tag','rtag','commitindex'}
def events(text,prefix):
    return [dict((k,int(v,16 if k in HEX else 10)) for k,v in re.findall(r'(\w+)=(\w+)',l))
            for l in text.splitlines() if l.startswith(prefix+' ')]
def rtl(m):return {n:h for n,h in m['source']['files'].items() if n.startswith('rtl/') and Path(n).suffix in ['.v','.sv','.svh']}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--five-f',default='step5k-5f-01');p.add_argument('--previous',default='step5k-p1-01')
    p.add_argument('--candidate',default='step5k-lookup-02');a=p.parse_args()
    dirs={k:ROOT/'build/sim/cpu-load-lookup'/v for k,v in vars(a).items()}
    results={k:load(d/'result.json') for k,d in dirs.items()}
    assert all(r['status']=='PASS' for r in results.values())
    baseline=results['five_f']
    manifests={k:r['manifest'] for k,r in results.items()}
    rr={k:rtl(m) for k,m in manifests.items()};assert all(len(x)==60 for x in rr.values())
    assert all(r['programs']==baseline['programs'] and r['oracle']==baseline['oracle'] for r in results.values())
    assert all(m['fixtures']==manifests['five_f']['fixtures'] and m['image_id']==manifests['five_f']['image_id'] for m in manifests.values())
    assert [n for n in rr['five_f'] if rr['previous'][n]!=rr['five_f'][n]]==['rtl/arm/zap_core.sv']
    assert [n for n in rr['previous'] if rr['candidate'][n]!=rr['previous'][n]]==['rtl/arm/zap_core.sv']
    for n,h in rr['five_f'].items():
        assert sha(subprocess.check_output(['git','show',BASE+':'+n],cwd=ROOT))==sha((ROOT/n).read_bytes())==h
    assert sha((HERE/'rtl/arm/zap_core.sv').read_bytes())==rr['candidate']['rtl/arm/zap_core.sv']
    assert sha((ROOT/'tests/cpu/cpu_load_pipeline/rtl/arm/zap_core.sv').read_bytes())==rr['previous']['rtl/arm/zap_core.sv']
    receipt=dict(status='PASS',decision='Retain combined prototype for further qualification; production remains 5F',
                 manifests=manifests,variants={},comparisons=[],dependencies={},streams={})
    journals={};latencies={}
    for label,d in dirs.items():
        r=results[label];m=manifests[label]
        for n,h in m['fixtures'].items():assert sha((d/n).read_bytes())==h
        if (ROOT/m['executable']).exists():assert sha((ROOT/m['executable']).read_bytes())==m['executable_sha256']
        for n,h in m.get('driver_inputs',{}).items():assert sha((ROOT/n).read_bytes())==h
        traces={};windows={};latencies[label]={};streamstats={}
        for row in r['rows']:
            case=row['case'];iw,dw=row['profile'].split(':')
            text=log(d/f'{case}-{iw}-{dw}-0.log')
            pipe=events(text,'PIPE_WINDOW');hints=events(text,'LOOKUP_WINDOW')
            assert len(pipe)==len(hints)==len(row['windows'])
            assert len({w['cycles'] for w in row['windows'][row['warmups']:]})==1
            for w in row['windows'][row['warmups']:]:assert w['reads']==w['writes']==w['lines']==0
            mutations=512 if case.startswith('span-') else 384 if case=='transpose4' else 7 if case in ['stream','multiline'] else 1
            width=2 if case.startswith('span-') else 4
            for w in pipe[row['warmups']:]:
                assert w['ram_mutations']==w['store_acks']==mutations and w['mutated_bytes']==width*mutations
            windows[case+' '+row['profile']]=dict(pipeline=pipe,hints=hints)
            if row['profile']=='0:0':
                traces[case]={typ:events(text,typ) for typ in ['PIPE_EDGE','PIPE_ISSUE','PIPE_RET','LOOKUP_EDGE']}
        for pattern in ['forward','reverse']:
            case='span-'+pattern;tr=traces[case]
            iss=tr['PIPE_ISSUE'];ret=tr['PIPE_RET']
            assert [e['pc'] for e in iss]==[0x10093e38+4*(i%20) for i in range(10241)]
            assert [e['pc'] for e in ret]==[0x10093e38+4*(i%20) for i in range(10239)]
            measures={}
            for pc in [0x10093e38,0x10093e58,0x10093e7c]:
                starts=[e['t'] for e in iss if e['pc']==pc][:512]
                uses=[e['t'] for e in iss if e['pc']==pc+4][:512]
                assert len(starts)==len(uses)==512
                distances=[b-a for a,b in zip(starts,uses)]
                latencies[label][(pattern,pc)]=distances
                start=starts[7];end=uses[7]
                measures[hex(pc)]=dict(consumer=hex(pc+4),distances=distances,histogram=dict(Counter(distances)),
                    representative=[dict(e,t=e['t']-start) for e in tr['PIPE_EDGE'] if start<=e['t']<=end],
                    lookup=[dict(e,t=e['t']-start) for e in tr['LOOKUP_EDGE'] if start<=e['t']<=end])
            receipt['dependencies'][label+' '+pattern]=measures
        for case in ['stream','multiline']:
            tr=traces[case];lo,hi=0x10000008,0x10000408
            iss=[e for e in tr['PIPE_ISSUE'] if lo<=e['pc']<hi];ret=[e for e in tr['PIPE_RET'] if lo<=e['pc']<hi]
            assert [e['pc'] for e in iss]==[e['pc'] for e in ret]==list(range(lo,hi,4))
            assert all(e['last']==1 for e in iss)
            checked=[]
            for e in tr['PIPE_EDGE']:
                pc=e['p2pc']
                if e['comp'] and lo<=pc<hi and (pc-lo)%8==0:
                    index=(pc-lo)//8;expected=0x100+(index%8)*(8 if case=='multiline' else 1)
                    assert e['cf']==0 and e['cd']==expected
                    checked.append(pc)
            assert len(checked)==len(set(checked))==128
            steady=iss[16:240];gaps=Counter(b['t']-a['t'] for a,b in zip(steady,steady[1:]))
            measured=next(x for x in r['rows'] if x['case']==case and x['profile']=='0:0')
            normalized=lambda w:{k:v for k,v in w.items() if k!='index'}
            assert normalized(measured['windows'][2])==normalized(measured['windows'][measured['warmups']])
            streamstats[case]=dict(architectural_starts=256,architectural_retirements=256,checked_completion_values=128,
                                   steady_starts=224,steady_elapsed=steady[-1]['t']-steady[0]['t']+1,
                                   steady_gaps=dict(gaps),trace_window=2,
                                   trace_window_is_scored=(measured['warmups']==2),trace_metrics_equal_first_score=True)
        assert len([e for e in traces['transpose4']['PIPE_RET'] if 0x10000000<=e['pc']<0x10100000])==800
        safety=load(d/'safety.json');assert safety['status']=='PASS'
        receipt['streams'][label]=streamstats
        receipt['variants'][label]=dict(rows=r['rows'],oracles=r['oracle'],negatives=r['negatives'],windows=windows,safety=safety)
        journals[label]=traces
        compiler=d/'compiler-inputs.json';dat=(ROOT/m['executable']).parent/'Vbench__verFiles.dat'
        if dat.exists():
            names=set(re.findall(r'^S[^\n]*"/work/[^"\n]*/source/(rtl/[^"\n]+)"',dat.read_text(),re.M))
            compiler.write_text(json.dumps({n:rr[label][n] for n in sorted(names)},indent=2)+'\n')
        assert len(load(compiler))==51
    for (pattern,pc),old in latencies['previous'].items():
        assert all(a-b==1 for a,b in zip(old,latencies['candidate'][(pattern,pc)]))
        assert old==latencies['five_f'][(pattern,pc)]
    for case in journals['five_f']:
        assert all([e['pc'] for e in journal[case]['PIPE_RET']]==[e['pc'] for e in journals['five_f'][case]['PIPE_RET']] for journal in journals.values())
    for label,r in results.items():
        if label=='candidate':continue
        indexed={(x['case'],x['profile']):x for x in r['rows']}
        for row in results['candidate']['rows']:
            old=indexed[row['case'],row['profile']]
            receipt['comparisons'].append(dict(reference=label,case=row['case'],profile=row['profile'],old=old['cycles'],new=row['cycles'],
                                                clocks_saved=old['cycles']-row['cycles'],percent_reduction=100*(1-row['cycles']/old['cycles'])))
    diag=load(ROOT/'build/sim/cpu-load-lookup/step5k-diagnostics-01/result.json')
    assert diag['status']=='PASS' and diag['source_id']==manifests['candidate']['source']['source_id']
    pressure=load(ROOT/'build/sim/cpu-load-lookup/step5k-pressure-01/result.json');assert pressure['status']=='PASS'
    receipt['diagnostics']=diag;receipt['cache_guard_tests']=pressure
    out=ROOT/'docs/evidence/cpu-load-lookup-20261117.json'
    compressed=gzip.compress(json.dumps(journals,separators=(',',':')).encode(),mtime=0)
    out.with_suffix('.events.json.gz').write_bytes(compressed)
    receipt['events_sha256']=sha(compressed);receipt['analyzer_sha256']=sha(Path(__file__).read_bytes())
    out.write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    print('PASS three matched variants, 1536 earlier consumers per pattern, exact retirement/store/byte counts, streams and safety')

if __name__=='__main__':main()
