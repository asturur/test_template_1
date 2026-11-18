"""Attribute matched retirement intervals without adding overlapping stalls."""
from collections import Counter, defaultdict
from pathlib import Path
import gzip
import re
import statistics


def log_text(log):
    if log.is_file():
        return log.read_text()
    with gzip.open(log.with_suffix(log.suffix+'.gz'),'rt') as compressed:
        return compressed.read()


def events(log, prefix):
    return [{k:int(v,16 if k in ('pc','rpc','ipc','apc','va','target','fpc') else 10)
             for k,v in re.findall(r'(\w+)=([0-9a-f]+)',line)}
            for line in log_text(log).splitlines() if line.startswith(prefix+' ')]


def scan_correct(pc):
    # The ZAP journal initially used the updated CPSR on ARM BX. The
    # confirmed veneer PCs 35020 and 35030 are still ARM instructions.
    return pc-4 if pc in (0x10035024,0x10035034) else pc


def scan_class(pc,nxt):
    if pc in (0x10035020,0x10035030):
        return 'ARM BX to Thumb'
    if pc in (0x5055d2d4,0x5055d3de):
        return 'Thumb BX to ARM'
    if pc in (0x1001dce0,0x1001dce8):
        return 'taken BL' if nxt in (0x10035018,0x10035028) else 'skipped BL'
    if pc==0x1001dcf4:
        return 'pixel backedge'
    return 'other'


def scan_intervals(mainline, peer, tag='DONOR_EDGE'):
    runs=[[e for e in events(p,tag) if e['ret']]
          for p,tag in zip((mainline,peer),('ARCH_EDGE',tag))]
    # Start at the same first true original iteration. The timing markers
    # themselves are the same ARM NOPs even though these journals are bounded.
    runs=[rows[next(i for i,r in enumerate(rows) if r['rpc']==0x1001dcc4):] for rows in runs]
    last=min(len(r) for r in runs)
    runs=[r[:last] for r in runs]
    a,b=runs
    apcs=[scan_correct(r['rpc']) for r in a]
    bpcs=[scan_correct(r['rpc']) if tag=='ARCH_EDGE' else r['rpc'] for r in b]
    mismatch=next((i for i,(x,y) in enumerate(zip(apcs,bpcs)) if x!=y),None)
    assert mismatch is None,(mismatch,apcs[mismatch:mismatch+6],bpcs[mismatch:mismatch+6])
    end=max(i for i,pc in enumerate(apcs) if pc==0x1001dcc4)
    gaps=defaultdict(list)
    for i in range(end):
        kind=scan_class(apcs[i],apcs[i+1])
        gaps[kind].append((a[i+1]['t']-a[i]['t'], b[i+1]['t']-b[i]['t']))
    return dict(pixels=sum(pc==0x1001dcc4 for pc in apcs[:end]),
                clocks=[r[end]['t']-r[0]['t'] for r in runs],
                intervals={name:dict(count=len(items),totals=[sum(v) for v in zip(*items)],
                                      medians=[statistics.median(v) for v in zip(*items)],
                                      counts=[dict(Counter(v)) for v in zip(*items)])
                           for name,items in gaps.items()})


def span_recurrence(log, tag):
    edges=events(log,tag+'_EDGE')
    data=events(log,tag+'_DATA')
    ret=[r for r in edges if r['ret']]
    bases=[r['t'] for r in ret if r['rpc']==0x10056eb4]
    # The 19th visited pixel has both line-resident reads and the trained
    # backward branch. Align at the same first retired original instruction.
    start,end=bases[18:20]
    result=dict(pixel=19,span=end-start,operations={})
    for pc in (0x10056ec4,0x10056edc,0x10056ee0,0x10056efc):
        fire=[e for e in edges if e['alu'] and e['apc']==pc and
              start<=e['t']<end and (tag=='DONOR' or not e['stall'])]
        assert len(fire)==1,(tag,hex(pc),fire)
        retires=[e['t']-start for e in ret if e['rpc']==pc and start<=e['t']<end]
        assert len(retires)==1
        pops=[e['t']-start for e in edges if e.get('pop') and e.get('ipc')==pc and start<=e['t']<end]
        requests=[r for r in data if r['pc']==pc and start<=r['t']<end]
        result['operations'][hex(pc)]=dict(
            issue=pops,execute=fire[0]['t']-start,retire=retires[0],
            requests=[{**r,'t':r['t']-start} for r in requests])
    return result


if __name__=='__main__':
    import argparse,json
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('mainline',type=Path)
    p.add_argument('donor',type=Path)
    a=p.parse_args()
    print(json.dumps(scan_intervals(a.mainline,a.donor),indent=2))
