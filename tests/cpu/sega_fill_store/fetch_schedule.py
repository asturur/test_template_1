"""Attribute the original Sega fill recurrence to delivered instruction words."""
from collections import Counter
import gzip
import json

from schedule import ADD, BRANCH, CMP, MOV, PIXELS, PROFILES, STORE, lines, load, records, timing, peer

RUNS = {
    'tagged': 'fill-front-tagged-work-18',
    'donor': 'fill-front-donor-18',
}
LOOP = [MOV, STORE, ADD, CMP, BRANCH, MOV]
PC_FIELDS = {'launch', 'p1', 'p2', 'treq', 'target', 'fetched', 'fifo',
             'inflate', 'predecode', 'decode', 'f1', 'head'}


def frontend(path, stock):
    prefix = 'FRONT_DONOR ' if stock else 'FRONT '
    raw = [line for line in lines(path) if line.startswith(prefix)]
    edges = {}
    for line in raw:
        row = {k: int(v, 16 if k in PC_FIELDS else 10)
               for k, v in (token.split('=') for token in line.split()[1:])}
        edges[row['t']] = row
    assert list(edges) == list(range(1, len(raw) + 1))
    replies = [(edge['t'], edge['treq']) for edge in edges.values()
               if edge['req'] and edge['ack'] and not edge.get('retry')]
    recurrences = [replies[i:i+6] for i in range(len(replies)-5)
                   if [pc for _, pc in replies[i:i+6]] == LOOP]
    intervals = Counter()
    wait_total = Counter()
    silent_total = 0
    for recurrence in recurrences:
        times = [t for t, _ in recurrence]
        gaps = tuple(b-a for a, b in zip(times, times[1:]))
        intervals[gaps] += 1
        for t in range(times[0]+1, times[-1]+1):
            edge = edges[t]
            if not edge['req']:
                silent_total += 1
            elif not edge['ack']:
                wait_total[edge['treq']] += 1
        if stock:
            branch = edges[times[-2]-1]
            assert branch['pred'] and branch['f1'] == BRANCH and branch['launch'] == MOV
            assert all(edges[t]['push'] for t in range(times[0], times[-1]+1))
        else:
            branch = edges[times[-2]]
            assert branch['pred'] and branch['target'] == MOV
            assert all(not edges[t]['req'] for t in range(times[-2]+1, times[-2]+4))
            for index in (3, 5):
                service = [edges[t] for t in range(times[index]-5, times[index]+1)]
                assert all(e['req'] and e['treq'] == LOOP[index] and not e['i_tlb_busy'] for e in service)
                assert service[0]['i_accept'] and not any(e['ack'] for e in service[:-1])
                assert [e['i_state'] for e in service] == [0, 13, 10, 1, 2, 0]
                assert service[-1]['ack']

    if stock:
        assert set(intervals) == {(1, 1, 1, 1, 1)}
        assert not silent_total and not wait_total
    else:
        assert len(recurrences) == PIXELS-1
        assert set(intervals) == {(1, 1, 6, 1, 9)}
        assert silent_total == 3*len(recurrences)
        assert wait_total == {MOV: 5*len(recurrences), CMP: 5*len(recurrences)}
    return dict(groups=len(recurrences), waits=wait_total, no_request=silent_total,
                gaps=[dict(pattern=seq, count=n) for seq, n in intervals.items()]), raw


def main():
    paths = {name: peer.OUT / folder for name, folder in RUNS.items()}
    prior_path = peer.ROOT / 'docs/evidence/cpu-sega-fill-store-20261118.json.gz'
    with gzip.open(prior_path, 'rt') as f:
        prior = json.load(f)
    runs = {name: load(path / 'result.json') for name, path in paths.items()}
    report = dict(status='PASS', manifests={name: data['build'] for name, data in runs.items()}, profiles={})
    raw = {}
    for name, path in paths.items():
        stock = name == 'donor'
        prior_slot = 2 if stock else 0
        assert runs[name]['status'] == 'PASS'
        assert runs[name]['build']['source'] == prior['sources'][prior_slot]['source']
        for row in runs[name]['rows']:
            waits = row['profile']
            expected = prior['rows'][waits]['measurements'][prior_slot]
            assert row == expected
            log = path / f'sega-fill-{waits.replace(":", "-")}-0.log'
            exec_trace = records(log)
            execution = timing(exec_trace, stock)
            known = prior['rows'][waits]['summaries'][prior_slot]
            assert all(execution[k] == known[k] for k in ('clocks', 'retirements', 'mov_edges', 'add_edges'))
            assert execution['iteration_clocks'] == {int(k): v for k, v in known['iteration_clocks'].items()}
            if stock:
                assert all(e['fast'] for e in exec_trace['FILL_DONOR_ACK'])
            fetch, raw[f'{name} {waits}'] = frontend(log, stock)
            report['profiles'].setdefault(waits, {})[name] = dict(execution=execution, fetch=fetch)

    for waits in PROFILES:
        entries = report['profiles'][waits]
        a, b = (entries[k]['execution'] for k in ('tagged', 'donor'))
        normal = a['iteration_clocks'][18]
        assert b['iteration_clocks'][5] == normal == 510
        rare, = set(a['iteration_clocks'])-{18}
        donor_rare, = set(b['iteration_clocks'])-{5}
        boundary = lambda trace: trace['clocks'] - (trace['mov_edges'][-1]-trace['mov_edges'][0])
        entries['gap'] = dict(total=a['clocks']-b['clocks'], recurrent=normal*(18-5),
                              exceptional=rare-donor_rare, boundaries=boundary(a)-boundary(b))
        values = entries['gap']
        assert values['total'] == values['recurrent']+values['exceptional']+values['boundaries']
        print(waits, entries['gap'])
        print('  fetch', entries['tagged']['fetch'], entries['donor']['fetch'])
    for suffix, value in (('', report), ('.traces', raw)):
        path = peer.ROOT / f'docs/evidence/cpu-sega-fill-fetch-20261118{suffix}.json.gz'
        path.write_bytes(gzip.compress(json.dumps(value, sort_keys=True).encode(), mtime=0))


if __name__ == '__main__':
    main()
