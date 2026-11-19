"""Attribute fixed SDRAM replay clocks to request and pin events."""

import argparse
from bisect import bisect_right
from collections import Counter
from pathlib import Path
import json
from statistics import median

from payload_clocks import find

PATHS = ('v5', 'ngage2', 'interleaved', 'early_completion', 'early_scalar_admission')
CASES = ('fill16_frame', 'sega-scan')


def analyze(path, expected_count):
    requests, acknowledgements, columns, maintenance = [], [], [], []
    for record in path.read_text().splitlines():
        kind, clock, *fields = record.split()
        clock = int(clock)
        if kind == 'T':
            write, address, size = fields
            requests.append((clock, int(write), int(address, 16), int(size)))
        elif kind == 'A':
            acknowledgements.append(clock)
        elif kind == 'C':
            command = int(fields[0])
            if command in (4, 5):
                columns.append((clock, command))
            else:
                maintenance.append(clock)
        else:
            raise ValueError(f'Unexpected timeline event {kind}')
    assert len(requests) == expected_count + 1  # Includes the final drain read.
    assert len(acknowledgements) == len(requests)

    transfers = []
    pos = 0
    for request, ack in zip(requests, acknowledgements, strict=True):
        start, write, address, size = request
        beats = 2 if write or size == 32 else 1
        issued = columns[pos:pos + beats]
        assert len(issued) == beats and all(command == (4 if write else 5) for _, command in issued)
        transfers.append((start, write, address, ack, issued[0][0], issued[-1][0]))
        pos += beats
    assert pos == len(columns)

    phases = []
    for previous, current in zip(transfers, transfers[1:]):
        _, prev_w, prev_addr, prev_ack, prev_first, prev_last = previous
        start, write, address, ack, first, last = current
        if not (prev_w and write and prev_addr >> 10 == address >> 10):
            continue
        change = bisect_right(maintenance, prev_last)
        if change < len(maintenance) and maintenance[change] < first:
            continue
        phases.append((first - start, last - first, ack - last, start - prev_ack, first - prev_first))

    labels = ('request_to_first_pin_write', 'first_to_second_pin_write', 'second_pin_write_to_ack',
              'previous_ack_to_request', 'word_to_word')
    return dict(same_row_consecutive_pairs=len(phases),
                median_clocks=dict(zip(labels, map(median, zip(*phases)), strict=True)),
                word_cadences=dict(Counter(row[-1] for row in phases)))


def summarize(pin_runs):
    rows = {}
    for variant, name in enumerate(PATHS):
        cases = {}
        for case in CASES:
            base = pin_runs / f'trace-{variant}-{case}-2-64'
            log = base.with_suffix('.log')
            stats, = find(log, 'TRACE_RESULT ')
            assert 'PASS fixed post-L1 SDRAM trace' in log.read_text()
            stats.update(analyze(base.with_name(base.name + '-timeline.txt'), stats['requests']))
            cases[case] = stats
        rows[name] = cases
    for case in CASES:
        assert len({tuple(row[case][key] for key in ('requests', 'reads', 'writes')) for row in rows.values()}) == 1
    return rows


def phone_results(path):
    result = json.loads(path.read_text())
    assert result['status'] == 'PASS'
    return {row['case']: dict(median_clocks=row['median_clocks'],
                              scored_clocks=[w['cycles'] for w in row['windows'][2:]])
            for row in result['rows']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pin_runs', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--control', type=Path, help='checked full-phone control result.json')
    parser.add_argument('--candidate', type=Path, help='checked full-phone candidate result.json')
    args = parser.parse_args()
    result = dict(fixed_traces=summarize(args.pin_runs))
    if args.control and args.candidate:
        baseline, handoff = map(phone_results, (args.control, args.candidate))
        assert baseline.keys() == handoff.keys()
        result['full_phone'] = dict(v5=baseline, early_scalar_admission=handoff)
    args.output.write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
