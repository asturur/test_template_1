"""Audit the matched observations and write the comparison and compact receipt."""
import argparse
import gzip
import json
import math
from pathlib import Path
import statistics

from build import HERE, OUT, ROOT, digest, save, sha
from source import CHANGED

METRICS = ('hit1','hit2','hit3','dsearch','isearch','dwalk','iwalk','dhold','hold')
EFFECTS = ('index','pc_hash','store_hash','stores','instructions','retire_proxy',
           'payload_retire_proxy','helper_retire_proxy')
CASE_ORDER = (
    'matrix4', 'transpose4', 'triangle_edges', 'fill16_frame', 'fill16_tail', 'fill8_tail',
    'diffuse_m10_8x8_jpeg', 'diffuse_m10_8x8_random', 'diffuse_m8_8x8_random',
    'diffuse_m10_16x8_jpeg', 'monkey-forward', 'monkey-reverse',
    'monkey-forward-small', 'monkey-reverse-small', 'sega-span', 'sega-fill', 'sega-scan',
    'asphalt-table', 'asphalt-double', 'asphalt-single', 'arm-stream',
)


def read(path):
    return json.loads(path.read_text())


def load_runs(names, candidate):
    rows = {}
    for name in names:
        directory = OUT/name
        result = read(directory/'result.json')
        assert result['status']=='PASS', name
        manifest = result['build']
        assert manifest['candidate']==candidate, name
        for row in result['rows']:
            key = row['case'], row['profile']
            assert key not in rows, key
            rows[key] = row,manifest,directory
    assert rows.keys()=={(case,p) for case in CASE_ORDER for p in ('0:0','2:9')}
    return rows


def medians(row):
    return {m:statistics.median(w[m] for w in row['windows'][row['warmups']:])
            for m in METRICS}


def unpack(row):
    stats = medians(row)
    outside = {m:row['total'][m]-sum(w[m] for w in row['windows']) for m in row['total']}
    assert all(v>=0 for v in outside.values())
    return dict(cycles=row['median'],cycles_per_unit=row['cycles_per_unit'],
                medians=stats, windows=row['windows'], whole_run=row['total'],
                setup_checks_cleanup=outside, repeats_equal=row['repeats_equal'],
                wrong_output_rejected=row['wrong_output_rejected'])


def fifo(addresses, capacity):
    slots = []
    misses = 0
    for va in addresses:
        tag = va >> 10
        if tag not in slots:
            misses += 1
            slots = ([tag]+slots)[:capacity]
    return misses


def span_observed(row, directory):
    lines = (directory/(row['case']+'-0-0-0.log')).read_text().splitlines()
    trace = []
    for line in lines:
        if line.startswith('D_ACCESS '):
            fields = dict(word.split('=') for word in line.split()[1:])
            trace.append(dict(va=int(fields['va'],16),slot=int(fields['slot']),
                              miss=int(fields['miss']),write=int(fields['wr'])))
    assert len(trace)==4608
    assert sum(e['write'] for e in trace)==512
    misses = sum(e['miss'] for e in trace)
    assert misses == row['windows'][2]['misses']
    return trace


def stream_starts(directory):
    trace = directory/'arm-stream-0-0-0.log'
    slots = []
    for line in trace.read_text().splitlines():
        if line.startswith('D_EDGE '):
            fields = dict(word.split('=') for word in line.split()[1:])
            pc = int(fields['pc'],16)
            if fields['issue']=='1' and 0x10000048<=pc<0x100003c8:
                slots.append((pc,int(fields['t'])))
    assert [pc for pc,_ in slots]==list(range(0x10000048,0x100003c8,4))
    assert [cycle for _,cycle in slots]==list(range(slots[0][1],slots[0][1]+224))
    return slots


def paired(control, candidate):
    assert control.keys()==candidate.keys()
    rows, spans, traces, groups = [], {}, {}, {}
    for key,(a,ma,da) in control.items():
        b,mb,db = candidate[key]
        assert ma['harness']==mb['harness'] and ma['image']==mb['image']
        assert ma['source']['commit']==mb['source']['commit']
        sa,sb = ma['source']['files'],mb['source']['files']
        assert sa.keys()==sb.keys() and {p for p in sa if sa[p]!=sb[p]}==CHANGED
        groups[a['suite']] = {'control':ma,'candidate':mb}
        for field in ('operations','unit','oracle','variants','warmups'):
            assert a[field]==b[field], (key,field)
        assert len(a['windows'])==len(b['windows'])==7
        assert all({f:x.get(f) for f in EFFECTS}=={f:y.get(f) for f in EFFECTS}
                   for x,y in zip(a['windows'],b['windows'])), (key,'architectural effects')
        if a['suite']=='scan':
            assert all(w['stores']==a['oracle']['memory_writes']
                       for run in (a,b) for w in run['windows'])
        row = dict(case=key[0],profile=key[1],suite=a['suite'],operations=a['operations'],
                   unit=a['unit'],change_pct=(b['median']/a['median']-1)*100,
                   oracle=a['oracle'], programs=a['variants'], control=unpack(a),candidate=unpack(b))
        if key[1]=='0:0':
            if a['suite']=='stream':
                traces['arm-stream-starts'] = {'control':stream_starts(da),
                                                'candidate':stream_starts(db)}
            if a['suite']=='monkey':
                ta,tb = [span_observed(r,d) for r,d in ((a,da),(b,db))]
                assert [e['va'] for e in ta]==[e['va'] for e in tb]
                addresses = [e['va'] for e in ta]
                spans[key[0]] = dict(empty_fifo=[fifo(addresses,n) for n in (2,3)],
                    measured_misses=[sum(e['miss'] for e in t) for t in (ta,tb)],
                    prefixes=[t[:18] for t in (ta,tb)], scores=[a['windows'][2],b['windows'][2]],
                    addresses_sha256=digest(json.dumps(addresses).encode()))
                traces[key[0]+'-data'] = dict(control=ta,candidate=tb)
            if a['suite']=='monkey' or (row['change_pct']==0 and
                    row['control']['medians']['dsearch']!=row['candidate']['medians']['dsearch']):
                traces[key[0]] = {n:[l for l in (d/(key[0]+'-0-0-0.log')).read_text().splitlines()
                                    if l.startswith('D_EDGE ')]
                                  for n,d in (('control',da),('candidate',db))}
        rows.append(row)
    return rows, spans, traces, groups


def diagnostic_deltas(control, candidate):
    a,b = read(control),read(candidate)
    assert a['status']==b['status']=='PASS'
    assert len(a['rows'])==len(b['rows'])==22
    result = []
    for x,y in zip(a['rows'],b['rows']):
        assert x['name']==y['name'] and x['status']==y['status']
        result.append(dict(case=x['name'],control=x['cycles'],candidate=y['cycles']))
    return result


def table(rows):
    header = ('| Case | Waits | Work | Clocks A → B | Clocks/unit A → B | Δ clocks | '
              'D hits by slot A → B | Searches D/I A → B | Walks D/I A → B | D busy + hold A → B |')
    cells = [header,'| --- | --- | --- | ---: | ---: | ---: | --- | --- | --- | ---: |']
    order = {case:index for index,case in enumerate(CASE_ORDER)}
    for row in sorted(rows,key=lambda r:(order[r["case"]],r["profile"])):
        case = row['case']
        a,b = row['control'],row['candidate']
        work = f'{row["operations"]:,} {row["unit"]}'
        if row['suite']=='games':
            work += f', {row["oracle"]["stores"]:,} written'
        elif row['suite']=='scan':
            work += f', {row["oracle"]["written_pixels"]:,} written'
        am,bm = a['medians'],b['medians']
        def pair(*keys):
            return ' → '.join('/'.join(f'{m[k]:,}' for k in keys) for m in (am,bm))
        cells.append(f'| {case} | {row["profile"]} | {work} | {a["cycles"]:,} → {b["cycles"]:,} | '
                     f'{a["cycles_per_unit"]:,.2f} → {b["cycles_per_unit"]:,.2f} | '
                     f'{row["change_pct"]:+.2f}% | {pair("hit1","hit2","hit3")} | '
                     f'{pair("dsearch","isearch")} | {pair("dwalk","iwalk")} | {pair("dhold")} |')
    return '\n'.join(cells)+'\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--control',action='append',required=True)
    parser.add_argument('--candidate',action='append',required=True)
    parser.add_argument('--units',required=True)
    parser.add_argument('--diagnostics-control',type=Path,required=True)
    parser.add_argument('--diagnostics-candidate',type=Path,required=True)
    parser.add_argument('--core-control',type=Path,required=True)
    parser.add_argument('--core-candidate',type=Path,required=True)
    parser.add_argument('--evidence',type=Path,required=True)
    parser.add_argument('--table',type=Path,required=True)
    args = parser.parse_args()
    a,b = load_runs(args.control,False),load_runs(args.candidate,True)
    rows,spans,traces,manifests = paired(a,b)
    six_kernel = {}
    for profile in ('0:0','2:9'):
        kernels = [r for r in rows if r['suite']=='spmark' and r['profile']==profile]
        assert len(kernels)==6
        six_kernel[profile] = math.exp(statistics.mean(
          math.log(r['control']['cycles']/r['candidate']['cycles']) for r in kernels))
    units = read(OUT/args.units/'result.json')
    assert units['status']=='PASS' and sum(x['negative_rejected'] for x in units['rows'])==1
    core = {'control':read(args.core_control),'candidate':read(args.core_candidate)}
    assert all(x['status']=='PASS' and len(x['rows'])==10 for x in core.values())
    anchor = manifests['stream']
    for side, path in (('control',args.diagnostics_control),('candidate',args.diagnostics_candidate)):
        expected = anchor[side]['source']
        assert read(path)['source_id']==expected['source_id']
        assert core[side]['source']==expected
    diag = diagnostic_deltas(args.diagnostics_control,args.diagnostics_candidate)
    receipt = dict(status='PASS', rows=rows, manifests=manifests, six_kernel_throughput=six_kernel,
                   monkey_fifo=spans, units=units, cpu_diagnostics=diag, core_stimuli=core,
                   physical_area=None, physical_timing=None,
                   driver_hashes={p.name:sha(p) for p in HERE.iterdir() if p.is_file()})
    args.evidence.write_bytes(gzip.compress(json.dumps(receipt,sort_keys=True).encode(),mtime=0))
    args.evidence.with_name(args.evidence.name.removesuffix('.json.gz')+'.traces.json.gz').write_bytes(
        gzip.compress(json.dumps(traces,sort_keys=True).encode(),mtime=0))
    args.table.write_text(table(rows))
    print(six_kernel, 'rows', len(rows), 'monkey misses',
          {name: (s['empty_fifo'],s['measured_misses']) for name,s in spans.items()})


if __name__=='__main__':
    main()
