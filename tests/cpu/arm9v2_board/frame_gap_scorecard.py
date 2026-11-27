"""Summarize checked frame-gap replays from the archived simulation run names."""

from collections import Counter
from pathlib import Path
import argparse
import json
import statistics

from payload_clocks import OUT, ROOT, digest, find

REPLAYS = {
    'v5': 'frame-gap-v5-pin-profile',
    'early_restart': 'frame-gap-v5-pin-early',
    'posting': 'frame-gap-v5-pin-ordered-post',
    'interleave': 'frame-gap-v5-pin-interleave',
    'posting_and_interleave': 'frame-gap-v5-pin-post-interleave',
    'ngage2': 'frame-gap-donor-pins',
    'ngage2_scalar': 'frame-gap-donor-scalar',
    'ngage2_dcache16': 'frame-gap-donor-dcache16',
    'ngage2_dtlb_xor': 'frame-gap-donor-xor',
    'ngage2_dcache16_and_dtlb_xor': 'frame-gap-donor-matched',
    'v5_retained': 'frame-gap-v5-base-retained',
    'posting_and_interleave_retained': 'frame-gap-v5-post-interleave-retained',
    'v5_retained_pinwait': 'frame-gap-v5-base-pinwait-retained',
    'posting_and_interleave_retained_pinwait': 'frame-gap-v5-post-interleave-pinwait-retained',
}


def receipt(path):
    return json.loads(path.read_text())


def relative(path):
    return str(path.relative_to(ROOT))


def checked_frames(path):
    data = receipt(path)
    assert data['status'] == 'PASS', path
    rows = {}
    for case in data['rows']:
        windows = case['windows']
        cycles = [w['cycles'] for w in windows[2:]]
        assert len(cycles) == 5 and statistics.median(cycles) == case['median_clocks']
        rows[case['case']] = dict(
            median_clocks=case['median_clocks'], scored_clocks=cycles,
            first_scored=windows[2], last_scored=windows[-1],
            first_scored_memory=case.get('memory_windows', windows)[2],
        )
    return dict(archive=relative(path), identity={k: v for k, v in data.items() if k != 'rows'},
                cases=rows)


def one_record(path, label):
    rows = find(path, label)
    assert len(rows) == 1 and 'PASS ' in path.read_text(), path
    return rows[0]


def address_model(path):
    raw = path.read_bytes()
    requests = [(int(a, 16), int(we), int(width))
                for _, a, we, width in (line.split() for line in raw.decode().splitlines())]
    addresses = [a for a, _, _ in requests]
    stats = dict(sha256=digest(raw), requests=len(requests), top_byte_strides=Counter(
        abs(a - b) for a, b in zip(addresses, addresses[1:])).most_common(10))
    for name in ('v5', 'ngage2'):
        opened = {}
        counters = Counter()
        for address in addresses:
            if name == 'v5':
                bank, row = (address >> 23) & 1, (address >> 10) & 8191
            else:
                bank, row = (address >> 12) & 3, ((address >> 14) << 2) | ((address >> 10) & 3)
            if bank not in opened:
                counters['closed'] += 1
            elif opened[bank] == row:
                counters['hits'] += 1
            else:
                counters['conflicts'] += 1
            opened[bank] = row
        assert sum(counters.values()) == len(requests)
        stats[name] = dict(counters)
    return stats


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    archives = OUT / 'payload-clocks'
    frames = {label: checked_frames(archives / directory / 'result.json')
              for label, directory in REPLAYS.items()}
    groups = [('v5_retained', 'posting_and_interleave_retained'),
              ('v5_retained_pinwait', 'posting_and_interleave_retained_pinwait')]
    for control, candidate in groups:
        assert len(frames[control]['cases']) == 15
        assert frames[control]['cases'].keys() == frames[candidate]['cases'].keys()
    pins = OUT / 'frame-gap-bank-three-paths'
    paths = {'v5': 0, 'ngage2': 1, 'interleave': 2}
    stride_pins = {}
    scans = {}
    same_trace = {}
    row_model = {}
    for label, variant in paths.items():
        path = pins / f'run-{variant}.log'
        stride_pins[label] = find(path, 'BANK_RESULT ')
        assert len(stride_pins[label]) == 7
        scans[label] = one_record(path, 'SCAN_RESULT ')
        same_trace[label] = {case: one_record(pins / f'trace-{variant}-{case}-2-64.log', 'TRACE_RESULT ')
                             for case in ('fill16_frame', 'sega-scan')}
    for case in ('fill16_frame', 'sega-scan'):
        assert len({tuple(same_trace[leg][case][key] for key in ('requests', 'reads', 'writes'))
                    for leg in paths}) == 1
        row_model[case] = {
            'v5_stream': address_model(archives / REPLAYS['v5'] / f'{case}-2-64-requests.txt'),
            'ngage2_stream': address_model(archives / REPLAYS['ngage2'] / f'{case}-requests.txt'),
        }
    d2 = {leg: receipt(OUT / f'frame-gap-d2-{leg}' / 'receipt.json') for leg in ('base', 'early')}
    contract = OUT / 'arm9v2/contract-frame-gap-early-fault'
    fault = {f'{burst}:{wait}': one_record(contract / f'burst-{burst}-wait-{wait}.log', 'PASS ')
             for burst in (0, 1) for wait in (0, 5)}
    post_order = OUT / 'frame-gap-posted-order/run.log'
    assert 'PASS ordered SDRAM posting' in post_order.read_text()
    result = dict(
        native=dict(v5_fps=5.79, ngage2_fps=6.62, nominal_system_hz=78000000,
                    inferred_clock_difference=78000000 / 5.79 - 78000000 / 6.62,
                    independently_timed=False),
        timing_audit=dict(
            dll_sha256='5b918e3d10a8b4e91265325649c98c72fba7260be6cab37a102d7f50cd7eebef',
            euser_def_sha256='127908e636dd75fba96da6a40f63b4d70c53d42a00ca1b76da9bccdacf9593a5',
            score_base='0x10000000', utc_ordinal=1166, interval_ordinal=695, tick_count_ordinal=1137,
            fast_counter_imported=False, v5_timer_engine_hz=26000000, v5_timer_reload=406250,
            ngage2_timer_engine_hz=78000000 * 4 / 9, ngage2_timer_reload=0x843e2,
        ),
        frames=frames, stride_pins=stride_pins, sdram_frame_reads=scans, fixed_trace_pins=same_trace,
        row_model_without_refresh=row_model, delayed_nor=d2, fault_contract=fault,
        posting_order=relative(post_order),
    )
    args.output.write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
