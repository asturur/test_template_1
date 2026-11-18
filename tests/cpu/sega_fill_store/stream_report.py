"""Audit the instruction stream overlay against the exact tagged baseline."""
from collections import Counter
import gzip
import json
import math

from fetch_schedule import PC_FIELDS
from report import CASE_ORDER, EFFECTS
from schedule import ADD, BRANCH, CMP, MOV, PIXELS, PROFILES, STORE, lines, load, records, verify_writes, peer

RUNS = (
    ('arch-tagged-work-18-v2', 'arch-tagged-scan-work-18-v2'),
    ('fill-stream-matrix-18', 'fill-stream-scan-work-18'),
    ('fill-stream-path-matrix-18', 'fill-stream-path-scan-work-18'),
)
FOCUSED = ('fill-front-tagged-work-18', 'fill-stream-probe-work-18', 'fill-stream-path-work-18')
SOURCE_DELTAS = (
    set(),
    {'rtl/arm920/cache_access.sv'},
    {'rtl/arm920/cache_access.sv', 'rtl/arm/zap_cache.sv'},
)


def benchmark(names):
    rows = {}
    sources = []
    for name in names:
        run = load(peer.OUT / name / 'result.json')
        assert run['status'] == 'PASS', name
        sources.append(run['build'])
        for row in run['rows']:
            assert row['wrong_output_rejected'] and row['repeats_equal'] == 2
            key = row['case'], row['profile']
            assert key not in rows
            rows[key] = row
    assert rows.keys() == {(case, waits) for case in CASE_ORDER for waits in PROFILES}
    assert sources[0]['source'] == sources[1]['source']
    return rows, sources


def fetch_profile(log):
    front = []
    for line in lines(log):
        if line.startswith('FRONT '):
            front.append({k: int(v, 16 if k in PC_FIELDS else 10)
                          for k, v in (token.split('=') for token in line.split()[1:])})
    edges = records(log)
    verify_writes(edges, False)
    assert len(front) == len(edges['FILL_EDGE'])
    assert sum(e['retire'] for e in edges['FILL_EDGE']) == 2567
    executes = [e['t'] for e in edges['FILL_EDGE'] if e['aluvalid'] and not e['datastall'] and e['alu'] == MOV]
    assert len(executes) == PIXELS
    pcs = (MOV, STORE, ADD, CMP, BRANCH, MOV)
    deliveries = [e for e in front if e['req'] and e['ack'] and not any(
        e[k] for k in ('held', 'i_retry', 'alu_clear', 'dec_clear', 'wb_clear'))]
    groups = [deliveries[i:i+6] for i in range(len(deliveries)-5)
              if tuple(e['treq'] for e in deliveries[i:i+6]) == pcs]
    gaps = Counter(tuple(b['t']-a['t'] for a, b in zip(g, g[1:])) for g in groups)
    assert len(groups) >= 511
    for g in groups:
        branch = g[-2]['t']
        assert all(not e['req'] for e in front[branch:branch+3])
    window, = [e for e in edges['ARCH_WINDOW'] if e['index'] == 2]
    original = [
        line for line in lines(log)
        if line.startswith(('FRONT ', 'FRONT_STREAM ', 'FILL_EDGE ', 'FILL_RAM ', 'FILL_OFFER '))
    ]
    return dict(clocks=len(front), exec_intervals=Counter(b-a for a,b in zip(executes, executes[1:])),
                fetch_intervals=[dict(intervals=g, count=n) for g, n in sorted(gaps.items())],
                icache_demands=Counter(f'{e["treq"]:08x}' for e in front if e['i_accept']),
                fifo_full=sum(e['fifo_full'] for e in front), occupancy=window), original


def main():
    all_runs = [benchmark(names) for names in RUNS]
    baseline = all_runs[0][1][0]['source']['files']
    base_image = all_runs[0][1][0]['image']
    for (_, manifests), delta in zip(all_runs, SOURCE_DELTAS, strict=True):
        for m in manifests:
            assert m['image'] == base_image and m['source']['files'].keys() == baseline.keys()
            assert {k for k, v in baseline.items() if m['source']['files'][k] != v} == delta
    table = []
    for case in CASE_ORDER:
        for waits in PROFILES:
            rows = [runs[case, waits] for runs, _ in all_runs]
            reference = rows[0]
            for row in rows[1:]:
                assert all(row[k] == reference[k] for k in ('oracle', 'variants', 'operations', 'warmups'))
                for a, b in zip(reference['windows'], row['windows'], strict=True):
                    assert all(a.get(k) == b.get(k) for k in EFFECTS), (case, waits, a, b)
            if case == 'arm-stream':
                assert all(w['starts'] == w['start_clocks'] == 224 for row in rows for w in row['windows'][2:])
            table.append(dict(case=case, profile=waits, medians=[r['median'] for r in rows],
                              windows=[r['windows'] for r in rows]))
    measured = {}
    raw = {}
    for n, name in enumerate(FOCUSED):
        root = peer.OUT / name
        for waits in PROFILES:
            label = f'{name} {waits}'
            measured[label], raw[label] = fetch_profile(root / f'sega-fill-{waits.replace(":", "-")}-0.log')
            assert measured[label]['clocks'] == all_runs[n][0]['sega-fill', waits]['median']
    quality = {}
    for name, folder in (
        ('adapter', peer.OUT / 'fill-stream-unit-18'),
        ('control', peer.OUT / 'fill-stream-unit-control-18'),
        ('core', peer.OUT.parent / 'tlb-area/fill-stream-path-core-18'),
        ('diagnostics', peer.OUT.parent / 'tlb-area/fill-stream-path-diag-18'),
        ('interwork', peer.OUT / 'fill-stream-interwork-18'),
    ):
        item = load(folder / 'result.json')
        assert item['status'] == 'PASS'
        quality[name] = item
    assert [len(quality[k]['rows']) for k in ('core', 'diagnostics')] == [10, 22]
    control, retained, steered = (ms[0]['source'] for _, ms in all_runs)
    assert quality['adapter']['source'] == retained and not quality['adapter']['negative']
    assert quality['control']['source'] == control and quality['control']['negative']
    assert quality['core']['source'] == quality['interwork']['source'] == steered
    assert quality['diagnostics']['source_id'] == steered['source_id']
    assert len(quality['interwork']['rows']) == 3
    report = dict(status='PASS', table=table, focused=measured, qualification=quality,
                  manifests=[ms for _, ms in all_runs])
    for ext, value in (('', report), ('.traces', raw)):
        path = peer.ROOT / f'docs/evidence/cpu-icache-stream-20261118{ext}.json.gz'
        path.write_bytes(gzip.compress(json.dumps(value, sort_keys=True).encode(), mtime=0))
    for waits in PROFILES:
        sp = [r['medians'] for r in table if r['profile'] == waits and r['case'] in CASE_ORDER[:6]]
        print(waits, 'SPMark geometric speedup', [math.prod(r[0]/r[i] for r in sp)**(1/6) for i in (1, 2)])
    for row in table:
        print(row['case'], row['profile'], *row['medians'])


if __name__ == '__main__':
    main()
