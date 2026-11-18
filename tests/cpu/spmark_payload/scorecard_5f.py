#!/usr/bin/env python3
"""Audit the accepted 5F integrated scorecard from qualified saved results."""
import hashlib
import argparse
import json
import math
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
CASES = ['matrix4', 'transpose4', 'triangle_edges', 'fill16_frame',
         'fill16_tail', 'fill8_tail']
PROFILES = ['0:0', '2:9']
ACCEPTED = 'fae40167654949f9530e75eecd6d58c4fc74d013'
PATHS = {
    'review': 'build/sim/spmark-payload/dsp-full-product-production-20261116',
    '5f': 'build/sim/spmark-payload/postindex-candidate-01',
    'triangle': 'build/sim/spmark-payload/integrated-5f-triangle-01',
    'donor': 'build/sim/spmark-payload/ngage2-vs5c-donor06',
}


def load(path):
    return json.loads((ROOT / path).read_text())


def digest(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def geometric(values):
    return math.exp(sum(math.log(x) for x in values) / len(values))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--triangle', default=PATHS['triangle'],
                        help='qualified exact-5F triangle run directory, relative to repository')
    args = parser.parse_args()
    PATHS['triangle'] = args.triangle
    runs = {key: load(path + '/result.json') for key, path in PATHS.items()}
    manifests = {key: load(path + '/manifest.json') for key, path in PATHS.items()}
    review = load('docs/evidence/cpu-pipeline-review-20261116.json')
    original = load('docs/evidence/cpu-store-postindex-20261117.json')
    recovery = load('docs/evidence/cpu-store-postindex-recovery-20261117.json')
    donor = load('docs/evidence/ngage2-vs-5c-20261117.json')
    assert all(run['status'] == 'PASS' for run in runs.values())
    assert original['status'] == recovery['status'] == donor['status'] == 'PASS'
    assert digest(PATHS['review'] + '/result.json') == review['suite_result_sha256']
    compiled = recovery['compiled_RTL_sha256']
    assert len(compiled) == 60
    for name, expected in compiled.items():
        accepted = subprocess.check_output(['git', 'show', ACCEPTED + ':' + name], cwd=ROOT)
        assert hashlib.sha256(accepted).hexdigest() == expected, name
        for key in ['5f', 'triangle']:
            assert manifests[key]['source']['files'][name] == expected, (key, name)
    # The generic freezer also includes adoption metadata and patch 0078. This
    # changes its bundle ID without changing any compiled Verilog/include.
    a = manifests['5f']['source']['files']
    b = manifests['triangle']['source']['files']
    metadata_difference = sorted(n for n in a.keys() | b.keys() if a.get(n) != b.get(n))
    assert metadata_difference in [[], ['patches/zap/0078-admit-postindexed-word-stores.patch',
                                       'rtl/arm/README.md', 'rtl/arm/UPSTREAM.json']]
    for field in ['format', 'image_id', 'original_rom_sha256', 'payload_sha256',
                  'normal_import_link', 'original_images']:
        assert len({json.dumps(m[field], sort_keys=True) for m in manifests.values()}) == 1, field
    index = lambda rows: {(r['case'], r['profile']): r for r in rows}
    old = index(runs['review']['rows'])
    new = index(runs['5f']['rows'] + runs['triangle']['rows'])
    stock = index(runs['donor']['rows'])
    expected = {(c, p) for c in CASES for p in PROFILES}
    assert set(old) == set(new) == set(stock) == expected
    review_rows = {(r['case'], r['wait']): r for r in review['profiles']}
    accepted_rows = index(original['workloads'])
    donor_rows = index(donor['rows'])
    rows = []
    for case in CASES:
        for profile in PROFILES:
            key = case, profile
            group = [old[key], new[key], stock[key]]
            for field in ['program_sha256', 'oracle', 'payload_windows', 'operations', 'unit']:
                assert all(r[field] == group[0][field] for r in group), (key, field)
            assert old[key]['body_cycles_median'] == review_rows[key]['median']
            assert stock[key]['body_cycles_median'] == donor_rows[key]['ngage2']['cycles']
            if case != 'triangle_edges':
                assert new[key]['body_cycles_median'] == accepted_rows[key]['candidate']
                assert [w['cycles'] for w in new[key]['windows'][2:]] == accepted_rows[key]['candidate_scored']
            for run_key, run in runs.items():
                for r in [r for r in run['rows'] if (r['case'], r['profile']) == key]:
                    assert r['status'] == 'PASS' and r['deterministic_repeats'] == 2
                    assert len(r['windows']) == len(r['payload_windows']) == 7
                    assert all(w['retire_proxy'] == new[key]['windows'][2]['retire_proxy']
                               for w in r['windows'][2:])
                    assert any(q['case'] == case and q['status'] == 'PASS' and q['wrong_output_rejected']
                               for q in run['qualification'])
            v = {name: r['body_cycles_median'] for name, r in zip(['review', '5f', 'ngage2'], group)}
            rows.append(dict(case=case, profile=profile, cycles=v,
                             saved_cycles=v['review'] - v['5f'],
                             review_over_5f=v['review'] / v['5f'],
                             ngage2_over_5f=v['ngage2'] / v['5f'],
                             operations=new[key]['operations'], unit=new[key]['unit'],
                             cycles_per_operation=new[key]['cycles_per_operation'],
                             program_sha256=new[key]['program_sha256'], oracle=new[key]['oracle'],
                             windows={name: r['windows'] for name, r in zip(['review', '5f', 'ngage2'], group)},
                             original_payload_and_helper_counts=new[key]['payload_windows']))
    indices = {}
    for profile in PROFILES:
        group = [r for r in rows if r['profile'] == profile]
        assert len(group) == 6
        indices[profile] = {
            '5f_throughput_relative_to_review': geometric([r['review_over_5f'] for r in group]),
            'ngage2_throughput_relative_to_review': geometric([r['cycles']['review'] / r['cycles']['ngage2'] for r in group]),
            'ngage2_throughput_relative_to_5f': geometric([r['cycles']['5f'] / r['cycles']['ngage2'] for r in group]),
        }
    jpeg_path = 'build/sim/jpeg-payload/postindex-jpeg-02'
    jpeg = load(jpeg_path + '/result.json')
    jpeg_manifest = load(jpeg_path + '/manifest.json')
    old_jpeg_path = review['jpeg_source'].removesuffix('/result.json')
    old_jpeg = load(old_jpeg_path + '/result.json')
    old_jpeg_manifest = load(old_jpeg_path + '/manifest.json')
    assert jpeg['status'] == old_jpeg['status'] == 'PASS'
    for field in ['image_id', 'payload_sha256', 'rom_sha256']:
        assert jpeg_manifest[field] == old_jpeg_manifest[field], field
    for name, program in jpeg_manifest['programs'].items():
        assert program == old_jpeg_manifest['programs'][name], name
    jpeg_rows = []
    for profile in PROFILES:
        current = next(r for r in jpeg['rows'] if r['memory_profile'] == profile)
        before = next(r for r in old_jpeg['rows'] if r['memory_profile'] == profile
                      and r['case'] == current['case'])
        comparison = next(r for r in donor['jpeg']['rows'] if r['profile'] == profile)
        assert current['oracle'] == before['oracle']
        assert current['observation']['body_cycles_median'] == comparison['reference']['body_cycles_median'] == 84353
        assert current['observation']['windows'][2:] == comparison['reference']['windows'][2:]
        assert before['observation']['body_cycles_median'] == review['jpeg_median'] == 89610
        jpeg_rows.append(dict(profile=profile, review=89610, accepted_5f=84353,
                              stock_ngage2=comparison['donor']['body_cycles_median'],
                              review_over_5f=89610 / 84353,
                              windows=current['observation']['windows'],
                              excluded_from_six_kernel_index=True))
    receipt_paths = ['docs/evidence/' + name + '.json' for name in [
        'cpu-pipeline-review-20261116', 'cpu-store-postindex-20261117',
        'cpu-store-postindex-recovery-20261117', 'ngage2-vs-5c-20261117',
        'cpu-target-delivery-20261117', 'cpu-paired-delivery-20261117']]
    files = [path + '/' + name for path in PATHS.values() for name in ['manifest.json', 'result.json']]
    files += [jpeg_path + '/' + name for name in ['manifest.json', 'result.json']]
    evidence = dict(status='PASS', accepted_CPU_commit=ACCEPTED,
                    source_id=original['candidate_source_id'], triangle_freezer_source_id=manifests['triangle']['source']['source_id'],
                    metadata_only_source_bundle_differences=metadata_difference,
                    compiled_RTL_sha256=compiled, rows=rows, geometric_throughput_by_profile=indices,
                    separate_JPEG=jpeg_rows, input_receipt_sha256={p: digest(p) for p in receipt_paths + files},
                    source_runs=PATHS, new_run_executable_sha256=manifests['triangle']['executable_sha256'],
                    new_run_build_trees_retired=all(not (ROOT / PATHS['triangle'] / name).exists()
                                                   for name in ['obj', 'source']),
                    qualification='Original bytes/math/Unicorn/guards, seven windows, five scored, two exact repeats and wrong-output rejection for every row.',
                    harness_comparability='5F payload_tb adds passive post/metrics/drain observers to the maintained tb; unchanged scalar/line responder and marker boundaries. Donor uses its separately qualified observer and asymmetric matched backend contract.',
                    frame_drain_5f_2_9=[r['candidate_body_plus_first_empty'] for r in original['workloads'] if r['case'] == 'fill16_frame' and r['profile'] == '2:9'][0],
                    limitations=['Offline fixed-work CPU/cache throughput, not full SPMark points or phone speed.',
                                 'JPEG separate from six-case equal-weight geometric means.',
                                 'Stock donor JPEG reused from qualified archived receipt; its raw manifest was retired, so no fresh donor source/input re-audit is claimed.',
                                 'Donor selected top has 16/8KiB I/D versus 16/16KiB here; different associativity, TLB and miss policy.',
                                 'No new physical fit or frequency scaling included; pending-write first-empty is not a full cache clean.'],
                    next_experiment=dict(name='Warm resident line-transition probe ownership',
                                         direct_acceptance_stage_targets={'fill16_tail': 126, 'fill8_tail': 128},
                                         target_is_conditional_not_measured_savings=True,
                                         retention='At least4% fewer median cycles in each original tail at both profiles, no >0.5% other median regression, 71-cycle warm stores retained, all ordering/fault/IRQ/negative gates pass; exact cycle attribution and first issue/accept/RAM/retire traces required.'),
                    no_RTL_fit_CI_donor_or_hardware_changes=True)
    target = ROOT / 'docs/evidence/cpu-integrated-5f-20261117.json'
    target.write_text(json.dumps(evidence, indent=2) + '\n')
    print('PASS', target)
    print(json.dumps(indices, indent=2))


if __name__ == '__main__':
    main()
