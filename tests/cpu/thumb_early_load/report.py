"""Audit phase-matched Thumb comparisons, original effects and useful dependent timing."""
import argparse
from bisect import bisect_left, bisect_right
from collections import Counter, defaultdict
import gzip
import hashlib
import json
from pathlib import Path
import statistics
import struct
import sys

HERE = Path(__file__).resolve().parent
PEER = HERE.parent/'tlb_three_mapping'
sys.path.insert(0,str(PEER))
from build import OUT, ROOT, digest, sha
from report import CASE_ORDER, EFFECTS, stream_starts

CHANGED = {'rtl/arm/zap_core.sv','rtl/arm/zap_issue_main.sv','rtl/arm/zap_predecode_main.sv'}
EXACT = '0c380ab9bae92916d297b72d6a303d251f1d49d9'


def load(path):
    value=json.loads(path.read_text())
    assert value['status']=='PASS', path
    return value


def runs(names):
    rows={}
    for name in names:
        base=OUT/name
        result=load(base/'result.json')
        for row in result['rows']:
            key=row['case'],row['profile']
            assert key not in rows
            rows[key]=(row,result['build'],base)
    return rows


def check_effects(a,b):
    for key in ('case','profile','operations','unit','oracle','variants','warmups'):
        assert a[key]==b[key], (a['case'],key)
    for row in (a,b):
        assert len(row['windows'])==7 and row['repeats_equal']==2 and row['wrong_output_rejected']
    for x,y in zip(a['windows'],b['windows']):
        assert {k:x.get(k) for k in EFFECTS}=={k:y.get(k) for k in EFFECTS}, (a['case'],x['index'])
    if a['suite']=='scan':
        assert all(w['stores']==a['oracle']['memory_writes'] for row in (a,b) for w in row['windows'])


def strip_observer(path):
    text=path.read_text()
    monitor=(HERE/'observe.vh').read_text()
    assert text.startswith(monitor)
    text=text[len(monitor):]
    for task in ('begin','sample','end'):
        line=f'        thumb_{task}();\n'
        assert text.count(line)==1
        text=text.replace(line,'',1)
    return digest(text.encode())


def compare(archived,fresh,thumb):
    assert archived.keys()==thumb.keys()=={(case,p) for case in CASE_ORDER for p in ('0:0','2:9')}
    rows=[]
    for (name,profile),(b,mb,db) in thumb.items():
        old,mo,_=archived[(name,profile)]
        if (name,profile) in fresh:
            a,ma,da=fresh[(name,profile)]
            assert a['median']==old['median'] and a['total']==old['total']
            assert [{k:v for k,v in w.items() if k!='thumb'} for w in a['windows']]==old['windows']
            assert ma['harness']==mb['harness']
        else:
            a,ma,da=archived[(name,profile)]
        assert all(m['source']['commit']==EXACT for m in (ma,mb,mo))
        assert ma['image']==mb['image']==mo['image']
        assert ma['source']['files']==mo['source']['files']
        sa,sb=ma['source']['files'],mb['source']['files']
        assert sa.keys()==sb.keys() and {f for f in sa if sa[f]!=sb[f]}==CHANGED
        assert mo['harness']['tb.v']==mb['harness']['tb.v'] and mo['harness']['span.vh']==mb['harness']['span.vh']
        build=OUT/('thumb-early-scan-18-v2' if b['suite']=='scan' else 'thumb-early-18-v2')
        assert sha(build/'observe.vh')==mb['harness']['observe.vh']
        assert strip_observer(build/'observe.vh')==mo['harness']['observe.vh']
        check_effects(a,b)
        checked=a['windows'][a['warmups']:]
        assert not any(any(w.get('thumb',{}).values()) for w in checked)
        metrics=b['windows'][b['warmups']:]
        monitor={k:statistics.median(w['thumb'][k] for w in metrics) for k in metrics[0]['thumb']}
        assert all(w['thumb']['fault_pickup']==0 and w['thumb']['pickup']<=w['thumb']['use_high']+w['thumb']['use_low']
                   for w in metrics)
        if name=='arm-stream':
            assert all(w['starts']==w['start_clocks']==224 for run in (a,b) for w in run['windows'][2:])
            if profile=='0:0':
                assert len(stream_starts(da))==len(stream_starts(db))==224
        rows.append(dict(case=name,profile=profile,suite=b['suite'],operations=b['operations'],unit=b['unit'],
                         control=a['median'],candidate=b['median'],thumb=monitor,
                         pct=100*(b['median']/a['median']-1),control_windows=a['windows'],
                         candidate_windows=b['windows'],control_total=a['total'],candidate_total=b['total'],
                         input_variants=b['variants']))
    return rows


def journal(path):
    rows=defaultdict(list)
    for line in path.read_text().splitlines():
        if line.startswith(('THUMB_RET ','THUMB_EXEC ','THUMB_PICKUP ','THUMB_ACCEPT ')):
            tag,*fields=line.split()
            row=dict(field.split('=') for field in fields)
            rows[tag].append({k:int(v,16 if k in ('pc','producer') else 10) for k,v in row.items()})
    return rows


def dependent_timing(files,rom):
    old,new=map(journal,files)
    retiring=[p['THUMB_RET'] for p in (old,new)]
    assert [v['pc'] for v in retiring[0]]==[v['pc'] for v in retiring[1]]
    rpcs=defaultdict(list)
    for idx,row in enumerate(retiring[1]):
        rpcs[row['pc']].append(idx)
    retire_ticks=[v['t'] for v in retiring[1]]
    executes=[defaultdict(list),defaultdict(list)]
    for t,p in zip(executes,(old,new)):
        for e in p['THUMB_EXEC']:
            t[e['pc']].append(e['t'])
    accepted,pickups=new['THUMB_ACCEPT'],new['THUMB_PICKUP']
    assert len(accepted)==len(pickups)>0
    rows=[]
    for accept,pickup in zip(accepted,pickups):
        assert pickup['pc']==accept['pc'] and pickup['t']>=accept['t'] and not pickup['fault']
        use=accept['pc']
        prod=accept['producer']
        candidates=rpcs[use]
        consumer=candidates[bisect_left(candidates,bisect_left(retire_ticks,pickup['t']))]
        prior=rpcs[prod]
        producer=prior[bisect_left(prior,consumer)-1]
        assert 0<=producer<consumer
        # Thumb pipeline PCs are biased by four, while the shared bench logs -8.
        addr=prod+4
        op,=struct.unpack_from('<H',rom,addr-0x50000000)
        assert op&0xf800 in (0x6800,0x9800), (hex(addr),hex(op))
        samples=[]
        for ret,exe in zip(retiring,executes):
            pr,cr=ret[producer]['t'],ret[consumer]['t']
            pe=exe[prod][bisect_right(exe[prod],pr)-1]
            ce=exe[use][bisect_right(exe[use],cr)-1]
            assert pe<=ce<=cr and pe<=pr<=cr
            samples.append(dict(execute=ce-pe,retire=cr-pr,producer_execute=pe,consumer_execute=ce,
                                producer_retire=pr,consumer_retire=cr))
        rows.append(dict(producer_pc=hex(addr),consumer_pc=hex(use+4),producer_ordinal=producer,
                         consumer_ordinal=consumer,control=samples[0],candidate=samples[1]))
    assert len({r['consumer_ordinal'] for r in rows})==len(rows)
    return dict(pairs=rows,execute_delta=dict(Counter(
        r['candidate']['execute']-r['control']['execute'] for r in rows)),
        retire_delta=dict(Counter(r['candidate']['retire']-r['control']['retire'] for r in rows)))


def cpu_regressions():
    root=OUT.parent/'tlb-area'
    result={}
    references=(('third-d-control-diagnostics','thumb-early-cpu-18','cycles'),
                ('third-d-control-core','thumb-early-core-18','events'))
    for control,candidate,metric in references:
        a,b=[load(root/name/'result.json') for name in (control,candidate)]
        rows=[]
        assert len(a['rows'])==len(b['rows'])
        for x,y in zip(a['rows'],b['rows']):
            test=x.get('name',x.get('case'))
            assert test==y.get('name',y.get('case')) and x['latency']==y['latency']
            assert x[metric]==y[metric]
            rows.append(dict(test=test,latency=x['latency'],result=y[metric]))
        result[metric]=rows
    return result


def scorecard(rows):
    lines=['| Workload | Waits | 5L → Thumb clocks | Δ elapsed | Early starts low/high | Useful late pickups |',
           '| --- | --- | ---: | ---: | ---: | ---: |']
    for row in sorted(rows,key=lambda r:(CASE_ORDER.index(r['case']),r['profile'])):
        m=row['thumb']
        lines.append(f'| {row["case"]} | {row["profile"]} | {row["control"]:,} → {row["candidate"]:,} | '
                     f'{row["pct"]:+.2f}% | {m["p1_low"]:,}/{m["p1_high"]:,} | {m["pickup"]:,} |')
    return '\n'.join(lines)+'\n'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence',type=Path,required=True)
    parser.add_argument('--table',type=Path,required=True)
    args=parser.parse_args()
    prior=runs(['exp1-5l-matrix-v2','exp1-scan-baseline-v1'])
    fresh=runs(['thumb-control-work-18-v2'])
    candidate=runs(['thumb-early-work-18-v2','thumb-early-scan-work-18-v2'])
    rows=compare(prior,fresh,candidate)
    banked=runs(['banked-third-work-18-v1'])
    unbanked=runs(['exp1-3d-matrix-v1'])
    banked_rows=[]
    for key,(row,manifest,_) in banked.items():
        ctrl=unbanked[key][0]
        check_effects(ctrl,row)
        assert ctrl['median']==row['median']
        banked_rows.append(dict(case=key[0],profile=key[1],cycles=row['median'],windows=row['windows'],
                                whole_run=row['total']))
    rom=(ROOT/'build/firmware/nem4-factory/core.bin').read_bytes()
    dependencies={}
    for key,(_,_,db) in candidate.items():
        if key[1]=='0:0' and key[0].startswith('diffuse_'):
            da=fresh[key][2]
            filename=key[0]+'-0-0-0.log'
            timing=dependent_timing([da/filename,db/filename],rom)
            count=next(r['thumb']['pickup'] for r in rows if (r['case'],r['profile'])==key)
            assert len(timing['pairs'])==count
            dependencies[key[0]]=timing
            print(key[0],count,timing['execute_delta'],timing['retire_delta'])
    directed={side:load(OUT/f'thumb-directed-{side}-v3/result.json') for side in ('control','candidate')}
    assert directed['control']['guest_sha256']==directed['candidate']['guest_sha256']
    delayed=load(OUT/'banked-third-delayed-fill-v1/result.json')
    assert len(directed['control']['rows'])==len(directed['candidate']['rows'])==3
    record=dict(status='PASS',rows=rows,latent_dependency_pairs=dependencies,directed=directed,
        banked_third_smoke=banked_rows,banked_delayed_fill=delayed,cpu_regressions=cpu_regressions(),
        manifests={'control':fresh[('arm-stream','0:0')][1],
                   'candidate':candidate[('arm-stream','0:0')][1],
                   'archived_scan':prior[('sega-scan','0:0')][1],
                   'candidate_scan':candidate[('sega-scan','0:0')][1],
                   'combined_banked_third':manifest},
        driver_hashes={p.name:sha(p) for p in HERE.iterdir() if p.is_file()})
    args.evidence.write_bytes(gzip.compress(json.dumps(record,sort_keys=True).encode(),mtime=0))
    args.table.write_text(scorecard(rows))
    print('PASS',len(rows),'A/B rows,',len(banked_rows),'combined smoke rows')


if __name__=='__main__':
    main()
