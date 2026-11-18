"""Audit all original fill writes and compare the measured pipeline boundaries."""
import argparse
from collections import Counter, defaultdict
import gzip
import json
from pathlib import Path

from experiment import peer, TAGGED_RECEIPT

MOV = 0x1001C9F4
STORE, ADD, CMP, BRANCH = range(MOV + 4, MOV + 20, 4)
CASES = ('fill-store-tagged-work-18', 'fill-store-strh-work-18-v2', 'fill-store-stock-donor-18')
PROFILES = ('0:0', '2:9')
ADDRESS = 0x80008000
VALUE = 0xB67D
PIXELS = 512
HEX_FIELDS = {'pc', 'rpc', 'selected', 'issue', 'shift', 'alu', 'alu_result',
              'alu_va', 'alu_mask', 'result', 'va', 'mask', 'data'}


def load(path):
    return json.loads(path.read_text())


def lines(path):
    if path.exists():
        return path.read_text().splitlines()
    with gzip.open(path.with_suffix('.log.gz'), 'rt') as log:
        return log.read().splitlines()


def records(path):
    events = defaultdict(list)
    for line in lines(path):
        if line.startswith(('FILL_', 'ARCH_WINDOW ', 'ARCH_EFFECT ', 'DONOR_EFFECT ')):
            name, *words = line.split()
            fields = dict(word.split('=') for word in words)
            events[name].append({key: int(value, 16 if key in HEX_FIELDS or key == 'stores' else 10)
                                 for key, value in fields.items()})
    return events


def verify_writes(events, stock):
    if stock:
        accepted = completed = events['FILL_DONOR_ACK']
        physical = events['FILL_DONOR_RAM']
    else:
        accepted = [e for e in events['FILL_OFFER'] if e['accept']]
        completed = [e for e in events['FILL_OFFER'] if e['ack']]
        physical = events['FILL_RAM']
    assert len(accepted) == len(completed) == len(physical) == PIXELS
    for index, (accept, done, write) in enumerate(zip(accepted, completed, physical, strict=True)):
        va = ADDRESS + 2 * index
        lanes = 12 if va & 2 else 3
        for edge in (accept, done):
            assert edge['va'] == (va & ~3 if stock else va)
            assert edge['mask'] == lanes and edge['data'] == VALUE * 0x10001
        offset = va & (15 if stock else 31)
        assert write['mask'] == 3 << offset
        assert (write['data'] >> (8 * offset)) & 0xFFFF == VALUE
        if stock:
            assert write['va'] == va & ~3
        else:
            assert write['segment'] == (va >> 5) & 7
            assert accept['t'] <= min(done['t'], write['t'])
    return accepted, completed, physical


def timing(events, stock):
    edges = events['FILL_DONOR_EDGE' if stock else 'FILL_EDGE']
    assert [edge['t'] for edge in edges] == list(range(1, len(edges) + 1))
    accepted, completed, physical = verify_writes(events, stock)
    executions = defaultdict(list)
    for edge in edges:
        if (edge['execute'] if stock else edge['aluvalid'] and not edge['datastall']):
            executions[edge['pc' if stock else 'alu']].append(edge)
    starts = [e['t'] for e in executions[MOV]]
    assert len(starts) == PIXELS
    retires = [e['rpc'] for e in edges if e['retire'] and MOV <= e['rpc'] <= BRANCH]
    assert retires == [MOV, STORE, ADD, CMP, BRANCH] * PIXELS
    for pc in (STORE, ADD, CMP):
        assert len(executions[pc]) == PIXELS
    for index, (index_edge, store_edge) in enumerate(zip(executions[MOV], executions[STORE], strict=True)):
        value = index_edge['result' if stock else 'alu_result']
        va = ADDRESS + 2 * index
        assert value == 2 * (index + 3)
        assert store_edge['va' if stock else 'alu_va'] == va
        assert store_edge['mask' if stock else 'alu_mask'] == (12 if va & 2 else 3)

    iterations = Counter(b - a for a, b in zip(starts, starts[1:]))
    target_gaps = Counter()
    target_empty = 0
    index_locks = 0
    branch_locks = 0
    store_holds = 0
    queued_add_holds = 0
    occupancy = {}
    if not stock:
        for edge in edges:
            store_hold = edge['datastall'] and edge['selected'] == STORE
            store_holds += int(store_hold)
            add_present = any(edge[pc] == ADD and edge[valid] for pc, valid in
                              (('pc', 'valid'), ('issue', 'issuevalid'),
                               ('shift', 'shiftvalid'), ('alu', 'aluvalid')))
            queued_add_holds += int(store_hold and add_present)
            if edge['valid'] and edge['lock'] and not edge['datastall']:
                index_locks += int(edge['pc'] == STORE)
                branch_locks += int(edge['pc'] == BRANCH)
        occupancy, = [e for e in events['ARCH_WINDOW'] if e['index'] == 2]
        assert len(edges) == sum(occupancy[k] for k in ('hold', 'shift', 'dep', 'empty', 'other'))

    for index, (start, next_start) in enumerate(zip(starts, starts[1:])):
        block = edges[start - 1:next_start - 1]
        if stock:
            branch, = [e['t'] for e in block if e['execute'] and e['pc'] == BRANCH]
            next_issue = next_start
        else:
            branch, = [e['t'] for e in block if e['pop'] and e['pc'] == BRANCH]
            next_issue, = [e['t'] for e in block if e['pop'] and e['pc'] == MOV]
            target_empty += sum(not e['valid'] and not e['datastall']
                                for e in edges[branch:next_issue - 1])
        target_gaps[next_issue - branch] += 1
        if index == 5:
            add_issue = None if stock else next(e['t'] - start for e in block
                                                if e['pop'] and e['pc'] == ADD)
            sample = dict(iteration=6, index=executions[MOV][index]['result' if stock else 'alu_result'],
                          store_address=executions[STORE][index]['va' if stock else 'alu_va'],
                          store_address_time=executions[STORE][index]['t'] - start,
                          store_accept=accepted[index]['t'] - start,
                          store_completion=completed[index]['t'] - start,
                          physical_write=physical[index]['t'] - start,
                          add_issue=add_issue, add_execute=executions[ADD][index]['t'] - start,
                          branch_issue=branch - start, next_issue=next_issue - start,
                          next_execute=next_start - start)

    return dict(clocks=len(edges), retirements=sum(e['retire'] for e in edges),
                writes=len(physical), pipe_stores=sum(e.get('pipe', 0) for e in accepted),
                credits=sum(e.get('credit', 0) for e in accepted),
                credit_pixels=[i for i, e in enumerate(accepted) if e.get('credit', 0)],
                mov_edges=starts, add_edges=[e['t'] for e in executions[ADD]],
                store_holds=store_holds, queued_add_holds=queued_add_holds,
                index_locks=index_locks, branch_locks=branch_locks,
                occupancy=occupancy, iteration_clocks=dict(iterations),
                backedge_issue_gaps=dict(target_gaps), target_empty=target_empty, sample=sample)


def audit(paths):
    runs = [load(path / 'result.json') for path in paths]
    assert all(run['status'] == 'PASS' for run in runs)
    control, candidate, donor = [run['build'] for run in runs]
    with gzip.open(TAGGED_RECEIPT, 'rt') as f:
        archive = json.load(f)
    assert control['source'] == archive['manifests']['prototype']['standard']['source']
    assert control['harness'] == candidate['harness']
    assert control['image'] == candidate['image'] == donor['image']
    assert donor['source'] == archive['manifests']['donor']['standard']['source']
    control_files, candidate_files = (m['source']['files'] for m in (control, candidate))
    assert control_files.keys() == candidate_files.keys()
    assert {name for name, sha in control_files.items() if sha != candidate_files[name]} == {
        'rtl/arm/zap_core.sv', 'rtl/arm/zap_issue_main.sv', 'rtl/arm/zap_predecode_main.sv'
    }
    rows = {}
    for profile in PROFILES:
        row = [next(r for r in run['rows'] if r['profile'] == profile) for run in runs]
        assert all(r['case'] == 'sega-fill' and r['oracle'] == row[0]['oracle']
                   and r['variants'] == row[0]['variants'] and r['wrong_output_rejected']
                   and r['repeats_equal'] == 2 for r in row)
        log = [records(path / ('sega-fill-' + profile.replace(':', '-') + '-0.log')) for path in paths]
        ref, alt, stock = log
        assert ref['ARCH_EFFECT'] == alt['ARCH_EFFECT'] == stock['DONOR_EFFECT']
        assert len(ref['ARCH_EFFECT']) == 7 and all(w['count'] == PIXELS for w in ref['ARCH_EFFECT'])
        observed = [timing(data, i == 2) for i, data in enumerate(log)]
        for info, summary in zip(row, observed, strict=True):
            assert summary['clocks'] == info['median'] and summary['retirements'] == 2567
        control_timing, candidate_timing, _ = observed
        assert control_timing['mov_edges'] == candidate_timing['mov_edges']
        credits = set(candidate_timing['credit_pixels'])
        advances = [a - b for a, b in zip(control_timing['add_edges'],
                                          candidate_timing['add_edges'], strict=True)]
        assert advances == [2 if i in credits else 0 for i in range(PIXELS)]
        rows[profile] = dict(summaries=observed, measurements=row,
                             add_advance_clocks=dict(Counter(advances)))
    return dict(status='PASS', sources=[control, candidate, donor], rows=rows)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--traces', type=Path)
    args = parser.parse_args()
    runs = [peer.OUT / name for name in CASES]
    data = audit(runs)
    args.out.write_bytes(gzip.compress(json.dumps(data, sort_keys=True).encode(), mtime=0))
    if args.traces:
        traces = {f'{run.name} {waits}': [line for line in lines(run / f'sega-fill-{waits}-0.log')
                                       if line.startswith('FILL_')]
                  for run in runs for waits in ('0-0', '2-9')}
        args.traces.write_bytes(gzip.compress(json.dumps(traces, sort_keys=True).encode(), mtime=0))
    for waits, row in data['rows'].items():
        print(waits, [{k: s[k] for k in ('clocks', 'store_holds', 'credits', 'target_empty')}
                      for s in row['summaries']])
