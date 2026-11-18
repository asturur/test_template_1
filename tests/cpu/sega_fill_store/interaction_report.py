"""Audit exact faster-frontend A/B scores and useful Sega fill boundaries."""
from bisect import bisect_left
from collections import Counter
import gzip
import json
import math

from experiment import HERE, STORE_FILES, STREAM_RECEIPT
from report import CASE_ORDER, EFFECTS
from schedule import MOV, PIXELS, PROFILES, lines, load, records, timing, peer
from stream_report import fetch_profile

CONTROL = 'fill-stream-path-work-18'
CANDIDATE = 'fill-store-icache-work-18'
MATRIX = ('fill-store-icache-matrix-18', 'fill-store-icache-scan-work-18')
CONTROL_MATRIX = ('fill-stream-path-matrix-18', 'fill-stream-path-scan-work-18')


def focus(name, waits):
    path = peer.OUT / name / f'sega-fill-{waits.replace(":", "-")}-0.log'
    events = records(path)
    row = timing(events, False)
    pops = [e['t'] for e in events['FILL_EDGE'] if e['pop'] and e['pc'] == MOV]
    useful = [pops[bisect_left(pops, t)-1] for t in row['mov_edges']]
    assert all(i < t for i,t in zip(useful, row['mov_edges'], strict=True))
    assert all(a < b for a,b in zip(useful, useful[1:]))
    assert all(t < i for t,i in zip(row['mov_edges'][:-1], useful[1:], strict=True))
    row['useful_mov_dequeues'] = useful
    row['next_issue_intervals'] = Counter(b-a for a,b in zip(useful,useful[1:]))
    row.pop('sample')  # The long-pipeline sample is ambiguous once two pixels overlap.
    fetch, _ = fetch_profile(path)
    row['fetch'] = {k: fetch[k] for k in ('fetch_intervals','fifo_full','icache_demands')}
    raw = [l for l in lines(path) if l.startswith(('FILL_', 'FRONT ', 'FRONT_STREAM '))]
    return row, events['ARCH_EFFECT'], raw


def read_run(name):
    run = load(peer.OUT / name / 'result.json')
    assert run['status'] == 'PASS'
    return run


def main():
    with gzip.open(STREAM_RECEIPT, 'rt') as f:
        stream = json.load(f)
    source = stream['manifests'][2][0]['source']
    old, new = (read_run(name) for name in (CONTROL, CANDIDATE))
    assert old['build']['source'] == source
    delta = new['build']['source']['files']
    assert delta.keys() == source['files'].keys()
    assert {name for name, sha in delta.items() if sha != source['files'][name]} == STORE_FILES
    assert old['build']['harness'] == new['build']['harness']
    assert old['build']['image'] == new['build']['image']

    traces = {}
    targeted = {}
    for waits in PROFILES:
        a, x, traces[f'control {waits}'] = focus(CONTROL, waits)
        b, y, traces[f'candidate {waits}'] = focus(CANDIDATE, waits)
        assert x == y and all(e['count'] == PIXELS for e in x)
        legs = []
        for run, observed in ((old, a), (new, b)):
            row, = [r for r in run['rows'] if r['profile'] == waits]
            assert row['median'] == observed['clocks'] and row['repeats_equal'] == 2 and row['wrong_output_rejected']
            legs.append(row)
        assert all(legs[0][k] == legs[1][k] for k in ('oracle','variants','operations','warmups'))
        clock_saving = a['clocks'] - b['clocks']
        occupancy_delta = {k: b['occupancy'][k]-a['occupancy'][k] for k in ('hold','shift','dep','empty','other')}
        assert -sum(occupancy_delta.values()) == clock_saving
        issue_intervals = lambda v: [q-p for p,q in zip(v['useful_mov_dequeues'], v['useful_mov_dequeues'][1:])]
        paired_issue = Counter(zip(issue_intervals(a), issue_intervals(b), strict=True))
        targeted[waits] = dict(control=a, candidate=b, saving=clock_saving,
                               occupancy_delta=occupancy_delta,
                               variants=legs[0]['variants'],
                               paired_issue=[(x, y, n) for (x,y),n in sorted(paired_issue.items())])
        print(waits, a['clocks'], b['clocks'], clock_saving, occupancy_delta, paired_issue)

    baseline = {(r['case'],r['profile']):r for r in stream['table']}
    exact_control = {}
    for name in CONTROL_MATRIX:
        run = read_run(name)
        assert run['build']['source'] == source
        exact_control.update({(r['case'],r['profile']):r for r in run['rows']})
    assert exact_control.keys() == baseline.keys()
    checked = {}
    for name in MATRIX:
        run = read_run(name)
        assert run['build']['source'] == new['build']['source']
        assert run['build']['image'] == old['build']['image']
        for row in run['rows']:
            k = row['case'], row['profile']
            ref = baseline[k]
            original = exact_control[k]
            assert row['repeats_equal'] == 2 and row['wrong_output_rejected']
            assert all(row[field] == original[field] for field in ('oracle', 'variants', 'operations', 'warmups'))
            assert k not in checked
            for x,y in zip(ref['windows'][2], row['windows'], strict=True):
                assert all(x.get(f) == y.get(f) for f in EFFECTS), (k,x,y)
            assert row['oracle']['status'] == 'PASS'
            if k[0]=='arm-stream':
                assert all(w['starts'] == w['start_clocks'] == 224 for w in row['windows'][2:])
            checked[k] = dict(tagged=ref['medians'][0], one_file=ref['medians'][1],
                              control=ref['medians'][2], candidate=row['median'], windows=row['windows'])
    assert checked.keys() == baseline.keys()
    paths = (('directed_reference', peer.OUT/'fill-store-icache-safety-control-18-v2'),
             ('directed_candidate', peer.OUT/'fill-store-icache-safety-18-v2'),
             ('core', peer.OUT.parent/'tlb-area/fill-store-icache-core-18'),
             ('diagnostics', peer.OUT.parent/'tlb-area/fill-store-icache-diag-18'))
    quality = {name: load(root/'result.json') for name,root in paths}
    assert all(value['status']=='PASS' for value in quality.values())
    assert quality['directed_reference']['source']==source
    assert quality['directed_candidate']['source']==quality['core']['source']==new['build']['source']
    assert quality['diagnostics']['source_id']==new['build']['source']['source_id']
    assert quality['directed_reference']['program']==quality['directed_candidate']['program']
    assert [len(quality[k]['rows']) for k in ('directed_reference','directed_candidate','core','diagnostics')]==[3,3,10,22]
    scorecard = [dict(case=case, waits=waits, **checked[case,waits]) for case in CASE_ORDER for waits in PROFILES]
    drivers = {name: peer.sha(HERE / name) for name in (
        'experiment.py', 'extension.py', 'interaction_report.py',
        'store_safety.py', 'store_safety.vh', 'store_safety.S', 'stream_retention.py')}
    result = dict(status='PASS', targeted=targeted, scorecard=scorecard, qualification=quality,
                  control=old['build'], candidate=new['build'], drivers=drivers)
    for ext,value in (('',result),('.traces',traces)):
        path = peer.ROOT / f'docs/evidence/cpu-icache-strh-20261118{ext}.json.gz'
        path.write_bytes(gzip.compress(json.dumps(value, sort_keys=True).encode(), mtime=0))
    for waits in PROFILES:
        spmark = [r for r in scorecard if r['waits'] == waits and r['case'] in CASE_ORDER[:6]]
        print(waits, 'SPMark geometric throughput vs tagged',
              math.prod(r['tagged']/r['candidate'] for r in spmark)**(1/6))
    for row in scorecard:
        print(row['case'], row['waits'], row['tagged'], row['one_file'], row['control'], row['candidate'])


if __name__ == '__main__':
    main()
