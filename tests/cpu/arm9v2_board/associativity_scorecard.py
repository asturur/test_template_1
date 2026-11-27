"""Verify and summarize the original, line-dirty, and half-dirty v5 trials."""
import argparse
from collections import defaultdict
import hashlib
import json
import math
from pathlib import Path
import re
import statistics

ROOT = Path(__file__).resolve().parents[3]
SIM = ROOT / 'build/sim'
WAYS = (2, 4, 8, 16, 32, 64)
PROFILES = ('0:0', '2:9')
RESULT = ROOT / 'docs/evidence/arm9v2-associativity-20261118.json'


def json_read(path):
    return json.loads(path.read_text())


def records(path, prefix):
    return [dict((key, int(value)) for key, value in re.findall(r'(\w+)=(\d+)', line))
            for line in path.read_text().splitlines() if line.startswith(prefix)]


def gather(leg, original=False):
    suffix_parent = 'v5-assoc-original' if original else leg
    specs = (
        ('spmark', SIM / 'spmark-payload' / leg, ''),
        ('games', SIM / 'arm9v2' / (suffix_parent + '-games'), 'arm9v2-'),
        ('scan', SIM / 'arm9v2' / (suffix_parent + '-sega'), 'arm9v2-'),
        ('jpeg', SIM / 'jpeg-payload' / (suffix_parent + '-jpeg'), ''),
    )
    rows = defaultdict(dict)
    references = {}
    jpeg_fixture = {}
    for group, path, log_prefix in specs:
        receipt = path / 'result.json'
        if not receipt.exists():
            continue
        try:
            data = json_read(receipt)
        except json.JSONDecodeError:
            # Some readers write their receipt while a run is still active.
            continue
        if data['status'] != 'PASS':
            continue
        references[group] = str(receipt.relative_to(ROOT))
        if group == 'jpeg':
            assert data['wrong_output_rejected']
            jpeg_fixture = {key: data['manifest'][key] for key in ('jpeg_sha256', 'rom_sha256', 'programs', 'oracle')}
        if group == 'spmark':
            assert len(data['qualification']) == 6 and all(case['wrong_output_rejected'] for case in data['qualification'])
        for row in data['rows']:
            if row.get('cpu', 'arm9v2') != 'arm9v2':
                continue
            case, profile = row['case'], row['profile']
            log_case = 'jpeg' if group == 'jpeg' else case
            prefix = f'{log_prefix}{log_case}-{profile.replace(":", "-")}'
            log = path / f'{prefix}-0.log'
            counter = {}
            for label, key in (('CACHE_WINDOW ', 'cache'), ('FETCH_WINDOW ', 'fetch')):
                window_records = records(log, label)
                if window_records:
                    assert len(window_records) == 7 and window_records == records(path / f'{prefix}-1.log', label)
                    counter[key] = window_records
            window_clocks = [item['cycles'] for item in row['windows']]
            assert len(window_clocks) == 7 and statistics.median(window_clocks[2:]) == row['body_cycles_median']
            assert row['status'] == 'PASS'
            if group in ('games', 'scan'):
                assert row['repeats'] == 2 and row['wrong_output_rejected']
            rows[case][profile] = dict(group=group, clocks=row['body_cycles_median'],
                                      window_clocks=window_clocks, cycles_per_operation=row.get('cycles_per_operation'),
                                      guest=row.get('guest'), oracle=row.get('oracle'),
                                      windows=row['windows'], counter=counter)
    if not rows:
        return None
    assert all(set(group) == set(PROFILES) for group in rows.values())
    if len(references) == len(specs):
        assert len(rows) == 15
    spmark_manifest = json_read(SIM / 'spmark-payload' / leg / 'manifest.json')
    return dict(rows=rows, references=references, source=spmark_manifest['source'],
                harness_sha256=spmark_manifest['harness_sha256'], image_id=spmark_manifest['image_id'],
                programs=spmark_manifest['programs'], payload_sha256=spmark_manifest['payload_sha256'],
                original_rom_sha256=spmark_manifest['original_rom_sha256'], jpeg_fixture=jpeg_fixture)


def index(ref, candidate, profile):
    comparisons = [old[profile]['clocks'] / candidate[name][profile]['clocks']
                   for name, old in ref.items() if old[profile]['group'] == 'spmark']
    assert len(comparisons) == 6
    return 100 * math.exp(statistics.mean(map(math.log, comparisons)))


def maintenance(leg, directed=False):
    stem = 'contract-' + leg + ('-directed' if directed else '')
    path = SIM / 'arm9v2' / stem
    output = {}
    for burst in (0, 1):
        for wait in (0, 5):
            log = path / f'burst-{burst}-wait-{wait}.log'
            if log.is_file() and records(log, 'PASS '):
                phases = records(log, 'ASSOC ')
                if len(phases) == 11:
                    output[f'{burst}:{wait}'] = phases
    return output if len(output) == 4 else {}


def summarize_counters(row):
    summary = {}
    retired = sum(window['retire_proxy'] for window in row['windows'][2:])
    for kind, windows in row['counter'].items():
        totals = {label: sum(window[label] for window in windows[2:])
                  for label in windows[0] if label != 'index'}
        summary[kind] = totals
    for label in ('i_fills', 'd_fills', 'd_responses'):
        if 'cache' in summary:
            summary[label + '_per_1000_retirements'] = 1000 * summary['cache'][label] / retired
    if 'fetch' in summary:
        fetch = summary['fetch']
        summary['i_accepted_per_1000_retirements'] = 1000 * fetch['accepted'] / retired
        for event in ('first_word', 'refill'):
            count = fetch[event + '_events']
            summary[event + '_clocks_per_match'] = fetch[event + '_clocks'] / count if count else None
    return summary


def split_cache_scan(name, control):
    path = SIM / 'arm9v2' / f'v5-assoc-{name}-sega' / 'result.json'
    if not path.is_file():
        return None
    try:
        data = json_read(path)
    except json.JSONDecodeError:
        return None
    if data['status'] != 'PASS':
        return None
    rows = {}
    for row in data['rows']:
        assert row['status'] == 'PASS' and row['repeats'] == 2 and row['wrong_output_rejected']
        profile = row['profile']
        assert row['guest'] == control[profile]['guest']
        assert row['oracle'] == control[profile]['oracle']
        rows[profile] = row['body_cycles_median']
    assert set(rows) == set(PROFILES)
    return dict(clocks=rows, source=data['sources']['arm9v2']['source'], receipt=str(path.relative_to(ROOT)))


def fetch_latency_control(name, control):
    path = SIM / 'spmark-payload' / f'v5-assoc-fetch-{name}'
    receipt = path / 'result.json'
    if not receipt.is_file():
        return None
    data = json_read(receipt)
    if data['status'] != 'PASS':
        return None
    for row in data['rows']:
        assert row['case'] == 'triangle_edges' and row['windows'] == control[row['profile']]['windows']
    profiles = {}
    for profile in PROFILES:
        prefix = 'triangle_edges-' + profile.replace(':', '-')
        windows = records(path / f'{prefix}-0.log', 'FETCH_WINDOW ')
        assert len(windows) == 7 and windows == records(path / f'{prefix}-1.log', 'FETCH_WINDOW ')
        profiles[profile] = windows
    return dict(windows=profiles, receipt=str(receipt.relative_to(ROOT)))


def print_tables(report):
    control = report['control']['rows']
    print('Each cell gives median CPU clocks at `0:0 / 2:9` added I:D waits.')
    for policy, title in (('line', 'Whole-line writebacks'), ('half', 'Half-line writebacks')):
        values = {ways: report['trials'].get(f'{policy}-{ways}', report['partial_trials'].get(f'{policy}-{ways}'))
                  for ways in WAYS}
        print(f'\n### {title}\n')
        headers = ['Stock two-way']
        if policy == 'line':
            headers = ['v4', 'Original ngage2'] + headers
        print('| Workload | ' + ' | '.join(headers + list(map(str, WAYS))) + ' |')
        print('| --- | ' + ' | '.join(['---:'] * (len(headers) + len(WAYS))) + ' |')
        for case, rows in control.items():
            comparisons = [rows] + [trial['rows'].get(case) if trial is not None else None for trial in values.values()]
            counts = [' / '.join(f"{entry[profile]['clocks']:,}" for profile in PROFILES) if entry else 'Pending'
                      for entry in comparisons]
            if policy == 'line':
                archived = report['archived']['rows'][case]
                counts = [' / '.join(f'{archived[profile][cpu]:,}' for profile in PROFILES)
                          for cpu in ('v4', 'ngage2')] + counts
            print('| ' + case + ' | ' + ' | '.join(counts) + ' |')
        for label, key in (('SPMark throughput vs. stock (%)', 'index_vs_two_way'),
                           ('SPMark throughput vs. prior ways (%)', 'index_vs_previous')):
            cells = []
            for trial in values.values():
                measure = trial.get(key) if trial is not None else None
                cells.append(' / '.join(f'{measure[profile]:.3f}' for profile in PROFILES) if measure else '—')
            print('| ' + label + ' | ' + ' | '.join(['—'] * len(headers) + cells) + ' |')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--markdown', action='store_true', help='print the per-workload Markdown tables')
    args = parser.parse_args()
    control = gather('v5-assoc-original-spmark', original=True)
    assert control is not None and len(control['rows']) == 15
    control['maintenance'] = maintenance('v5-assoc-production-directed-b')
    report = dict(base_commit='2a84b50', system_hz=78000000, target_hz=104000000,
                  cache_bytes_per_side=16384, line_bytes=32, flash_cache_bytes=8192, mmc_hz=39000000,
                  nos_hz=64, control=control, trials={}, partial_trials={})
    archived_path = RESULT.with_name('arm9v2-cache32-20261118.json')
    archived = json_read(archived_path)
    archived_rows = defaultdict(dict)
    for suite in archived['suites'].values():
        for row in suite['rows']:
            case, profile = row['case'], row['profile']
            assert row['clocks']['resized'] == control['rows'][case][profile]['clocks']
            assert row['windows']['resized'] == control['rows'][case][profile]['windows']
            archived_rows[case][profile] = {cpu: row['clocks'][cpu] for cpu in ('v4', 'ngage2')}
    report['archived'] = dict(source=str(archived_path.relative_to(ROOT)), rows=archived_rows,
                              v4_commit=archived['baseline_v4_commit'], ngage2_commit=archived['stock_ngage2_commit'])
    comparison_rows = {
        cpu: {case: {profile: {'clocks': archived_rows[case][profile][cpu], 'group': row[profile]['group']}
                     for profile in PROFILES}
              for case, row in control['rows'].items()}
        for cpu in ('v4', 'ngage2')
    }
    control['spmark_index_vs_archived'] = {
        cpu: {profile: index(rows, control['rows'], profile) for profile in PROFILES}
        for cpu, rows in comparison_rows.items()
    }
    report['overlays'] = {name: hashlib.sha256((ROOT / 'tools' / name).read_bytes()).hexdigest() for name in
                          ('arm9v2_cache_associativity.patch', 'arm9v2_cache_half_dirty.patch')}
    archived_fit = ROOT / 'build/fit/flash-d2-v5-20261118/comparison.json'
    if archived_fit.is_file():
        report['control_fit'] = json_read(archived_fit)['8192-2']
    for policy in ('line', 'packed', 'half'):
        for ways in WAYS:
            leg = f'v5-assoc-{policy}-{ways}'
            trial = gather(leg)
            if trial is None:
                continue
            for fixture in ('programs', 'payload_sha256', 'original_rom_sha256', 'image_id'):
                assert trial[fixture] == control[fixture]
            if trial['jpeg_fixture']:
                assert trial['jpeg_fixture'] == control['jpeg_fixture']
            prior_key = f'{policy}-{ways // 2}'
            previous = report['trials'].get(prior_key, report['partial_trials'].get(prior_key))
            trial['maintenance'] = maintenance(leg, directed=True) or maintenance(leg)
            for profile in PROFILES:
                for name, case in trial['rows'].items():
                    case[profile]['throughput_vs_two_way'] = control['rows'][name][profile]['clocks'] / case[profile]['clocks']
                    if previous is not None and name in previous['rows']:
                        case[profile]['throughput_vs_previous'] = previous['rows'][name][profile]['clocks'] / case[profile]['clocks']
                    assert case[profile]['guest'] == control['rows'][name][profile]['guest']
                    assert case[profile]['oracle'] == control['rows'][name][profile]['oracle']
                    case[profile]['scored_counters'] = summarize_counters(case[profile])
            trial['index_vs_two_way'] = {profile: index(control['rows'], trial['rows'], profile) for profile in PROFILES}
            if previous is not None and len(previous['rows']) == 15:
                trial['index_vs_previous'] = {profile: index(previous['rows'], trial['rows'], profile) for profile in PROFILES}
            trial['spmark_index_vs_archived'] = {
                cpu: {profile: index(rows, trial['rows'], profile) for profile in PROFILES}
                for cpu, rows in comparison_rows.items()
            }
            complete = len(trial['rows']) == 15
            report['trials' if complete else 'partial_trials'][f'{policy}-{ways}'] = trial
            if not args.markdown:
                scan = trial['rows'].get('sega-scan')
                print(policy, ways, trial['index_vs_two_way'], scan['2:9']['clocks'] if scan else 'scan pending')
    report['isolated_cache_scan'] = {}
    for name in ('i8-d2', 'i2-d8'):
        result = split_cache_scan(name, control['rows']['sega-scan'])
        if result is not None:
            report['isolated_cache_scan'][name] = result
    report['fetch_latency_control'] = {}
    for name in ('stock', 'line-2', 'line-4', 'line-8'):
        result = fetch_latency_control(name, control['rows']['triangle_edges'])
        if result is not None:
            report['fetch_latency_control'][name] = result
    for leg in ('line-2', 'packed-2'):
        if leg in report['trials']:
            repeat = report['trials'][leg]
            assert all(control['rows'][name][profile]['windows'] == repeat['rows'][name][profile]['windows']
                       for name in control['rows'] for profile in PROFILES)
            if control['maintenance'] and repeat['maintenance']:
                assert control['maintenance'] == repeat['maintenance']
    report['matched_primary_sweep_complete'] = all(f'{policy}-{ways}' in report['trials']
                                                  for policy in ('line', 'half') for ways in WAYS)
    report['matched_directed_sweep_complete'] = all(
        report['trials'].get(f'{policy}-{ways}', report['partial_trials'].get(f'{policy}-{ways}', {})).get('maintenance')
        for policy in ('line', 'half') for ways in WAYS)
    RESULT.write_text(json.dumps(report, indent=2) + '\n')
    if args.markdown:
        print_tables(report)


if __name__ == '__main__':
    main()
