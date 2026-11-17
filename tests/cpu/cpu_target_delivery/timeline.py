#!/usr/bin/env python3
"""Match committed dynamic control transfers to surviving target delivery."""
from pathlib import Path
from collections import defaultdict, Counter
from bisect import bisect_left, bisect_right
import gzip, re, json, hashlib, statistics, argparse

def read(path):
    return path.read_text() if path.exists() else gzip.open(str(path)+'.gz','rt').read()

def audit(path):
    es=[dict(re.findall(r'(\w+)=([^ ]+)',s)) for s in read(path).splitlines() if s.startswith('TARGET5E ')]
    assert es and all(int(b['e'])-int(a['e'])==1 for a,b in zip(es,es[1:]))
    maps={k:defaultdict(list) for k in ['flow','pre','rawpre','pop','decode','fetch','ack','btb']}
    retired=[]; suffixes=set(); clears=[]
    for i,e in enumerate(es):
        clear=any(e[k]=='1' for k in ['ac','wbc','dc'])
        if clear:clears.append(i)
        if e['pv']=='1' and not clear:maps['rawpre'][e['ppc']].append(i)
        if e['pa']=='1':
            maps['pre'][e['ppc']].append(i)
            ins=int(e['ins'],16)
            call=(ins&0x0f000000)==0x0b000000
            if call and ins>>34:suffixes.add(int(e['ppc'],16))
            if e['rn']!=e['ras']:
                maps['flow'][e['ppc']].append(i)
        if e['pop']=='1' and e['ac']==e['wbc']=='0':maps['pop'][e['opc']].append(i)
        if e['dv']=='1' and e['ac']==e['wbc']=='0':maps['decode'][e['dpc']].append(i)
        if e['fv']=='1' and e['code']=='0' and not clear:maps['fetch'][e['fpc']].append(i)
        if e['req']==e['ack']=='1' and not clear:maps['ack'][e['addr']].append(i)
        if e['btbc']=='1' and e['code']==e['saved']=='0' and int(e['pc3'],16)>>32 and not clear:
            maps['btb'][f"{int(e['pc3'],16)&0xffffffff:08x}"].append(i)
        if e['ret']=='1':retired.append((i,e['rpc']))
    canon=lambda pc:f'{int(pc,16)-(2 if int(pc,16) in suffixes else 0):08x}'
    def before(kind,pc,n,lower=-1):
        xs=maps[kind].get(pc,[]);j=bisect_right(xs,n)-1
        return xs[j] if j>=0 and xs[j]>lower else None
    def first(kind,pc,lo,hi):
        xs=maps[kind].get(pc,[]);j=bisect_left(xs,lo)
        return xs[j] if j<len(xs) and xs[j]<=hi else None
    def priority(e):
        if e['data']=='1':return 'data_write' if e['wr']=='1' else 'data_read'
        if e['busy']=='1':return 'multiply_busy'
        if e['oval']=='1' and e['ll']=='1':return 'load_lock'
        if e['oval']=='1' and e['sl']=='1':return 'shift_lock'
        if e['oval']=='0':return 'empty'
        return 'other'
    records=[]; used=set(); previous={}; occurrences=Counter(); union={}; overlap=0
    for ri,(r,pc) in enumerate(retired[:-1]):
        prev=previous.get(pc,-1);previous[pc]=r
        flow=before('flow',pc,r,prev)
        if flow is None:continue
        # Locate the actual dequeued source, then the accepted predecode owner.
        source_issue=first('pop',pc,flow,r)
        if source_issue is None:continue
        k=before('flow',pc,source_issue,prev)
        if k is None or k in used:continue
        e=es[k];used.add(k);ins=int(e['ins'],16);kind='call' if ins&0x0f000000==0x0b000000 else 'return'
        tr,tp=retired[ri+1];target=canon(tp)
        issue=first('pop',tp,k,tr)
        assert issue is not None,(path,pc,tp,es[r]['e'])
        dec=first('decode',tp,k,issue)
        assert dec is not None,(pc,tp,'decode')
        # An LDM/STM starts issuing before predecode releases its last uop.
        # Target availability therefore uses the valid head, not that release.
        pre=first('rawpre',tp,k,dec)
        assert pre is not None,(pc,tp,'pre')
        # Only fetches surviving the last frontend flush can feed this decode.
        # Choose the latest matching accepted F packet, not an earlier killed
        # request to the same repeated PC. Thumb BL consumes prefix+suffix.
        last_clear=clears[bisect_left(clears,pre)-1] if bisect_left(clears,pre) else -1
        fetch=before('fetch',target,pre,last_clear)
        assert fetch is not None,(pc,target,'fetch',es[pre]['e'])
        ack=before('ack',target,fetch-1)
        assert ack is not None,(pc,target,'ack')
        request=ack
        while request>0 and es[request-1]['req']=='1' and es[request-1]['addr']==target:request-=1
        prediction=before('btb',pc,k)
        if prediction is None and int(pc,16) in suffixes:prediction=before('btb',canon(pc),k)
        if prediction is not None and es[prediction]['btbt']!=e['pred'][-8:]:prediction=None
        for n in range(k,issue):
            if n in union:overlap+=1
            else:union[n]=kind
        correction=next((n for n in range(k,min(k+4,len(es))) if es[n]['dc']=='1' and es[n]['dt']==e['wt']),None) if e['wc']=='1' else None
        buckets=Counter(priority(x) for x in es[k:issue])
        front=Counter()
        for n in range(k,issue):
            x=es[n]
            if x['req']=='1' and x['addr']!=target and x['ack']=='0':front['held_other_fetch']+=1
            if x['req']=='1' and x['addr']==target and x['ack']=='0':front['target_ack_wait']+=1
            if x['tlb']=='1' or x['trans']=='1':front['translation_pipeline_busy']+=1
            if x['line']=='1' or x['scalar']=='1':front['external_bus_active']+=1
        row=dict(kind=kind,source=canon(pc),packet_pc=pc,occurrence=occurrences[(kind,canon(pc))],target=target,
            known=int(e['e']),prediction=int(es[prediction]['e']) if prediction is not None else None,
            predicted=e['pred'],needs_correction=e['wc']=='1',hint_target=e['wt'],hint_matches_actual=int(e['wt'],16)&~1==int(target,16),
            correction=int(es[correction]['e']) if correction is not None else None,
            source_issue=int(es[source_issue]['e']),source_retire=int(es[r]['e']),
            request=int(es[request]['e']),ack=int(es[ack]['e']),fetch=int(es[fetch]['e']),
            predecode=int(es[pre]['e']),decode=int(es[dec]['e']),issue=int(es[issue]['e']),retire=int(es[tr]['e']),
            buckets=dict(buckets),overlapping_front_conditions=dict(front))
        occurrences[(kind,canon(pc))]+=1;records.append(row)
    summaries={}
    for kind in ['call','return']:
        rr=[r for r in records if r['kind']==kind]
        summaries[kind]=dict(count=len(rr),sites=len({r['source'] for r in rr}),corrections=sum(r['needs_correction'] for r in rr),
            hint_mismatches=sum(not r['hint_matches_actual'] for r in rr),
            known_to={k:dict(median=statistics.median(r[k]-r['known'] for r in rr),histogram=dict(Counter(r[k]-r['known'] for r in rr))) for k in ['request','fetch','decode','issue','retire']},
            buckets=dict(sum((Counter(r['buckets']) for r in rr),Counter())))
    result=dict(path=str(path),edges=len(es),retirements=len(retired),retirement_PC_sha256=hashlib.sha256('\n'.join(pc for _,pc in retired).encode()).hexdigest(),
        canonical_retirement_histogram=dict(Counter(canon(pc) for _,pc in retired)),summaries=summaries,
        accepted_RAS_updates=sum(len(v) for v in maps['flow'].values()),unmapped_RAS_updates=sum(len(v) for v in maps['flow'].values())-len(used),
        covered_union=len(union),interval_overlap=overlap,union_buckets=dict(Counter(priority(es[n]) for n in union)),whole_buckets=dict(Counter(priority(e) for e in es)),
        records=records)
    return result

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('log',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
    result=audit(a.log);a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ['records','canonical_retirement_histogram']},indent=2))
