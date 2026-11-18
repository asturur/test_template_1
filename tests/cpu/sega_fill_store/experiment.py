"""Build or replay the original Sega Rally fill with explicit store timing."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import gzip
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ARCH = HERE.parent / 'cpu_architecture'
PEER = HERE.parent / 'tlb_three_mapping'
sys.path[:0] = [str(PEER), str(ARCH)]
import build as peer
from run import PROFILES, measure, prepare
from source import load, support

architecture = load('architecture_freezer', ARCH / 'build.py')
donor = load('architecture_donor', ARCH / 'donor.py')
TAGGED_RECEIPT = peer.ROOT / 'docs/evidence/cpu-state-tagged-fetch-20261118.json.gz'
STREAM_RECEIPT = peer.ROOT / 'docs/evidence/cpu-icache-stream-20261118.json.gz'
STORE_FILES = {'rtl/arm/zap_core.sv', 'rtl/arm/zap_predecode_main.sv', 'rtl/arm/zap_issue_main.sv'}
CASE = 'sega-fill'


def freeze(source, candidate=False, retain_stream=False, redirect_lookahead=False):
    reference = architecture.freeze(source, True, prototype=True)
    with gzip.open(TAGGED_RECEIPT, 'rt') as archived:
        tagged = json.load(archived)['manifests']['prototype']['standard']['source']
    assert reference == tagged
    if retain_stream or redirect_lookahead:
        import stream_retention as streaming
        streaming.apply(source)
        changed = {'rtl/arm920/cache_access.sv'}
        kind = 'tagged + resident I stream'
        if redirect_lookahead:
            streaming.redirect_lookahead(source)
            changed.add('rtl/arm/zap_cache.sv')
            kind += ' + redirect lookahead'
        variant = support.source_manifest(source, reference['commit'], kind)
        assert variant['files'].keys() == reference['files'].keys()
        assert {name for name, h in reference['files'].items() if variant['files'][name] != h} == changed
        if not candidate:
            return variant
        assert redirect_lookahead
        with gzip.open(STREAM_RECEIPT, 'rt') as archived:
            assert variant == json.load(archived)['manifests'][2][0]['source']
        reference = variant
    if not candidate:
        return reference
    from extension import apply
    apply(source)
    kind = reference['kind'] if redirect_lookahead else 'tagged'
    variant = support.source_manifest(source, reference['commit'], kind + ' + indexed STRH credit')
    assert set(variant['files']) == set(reference['files'])
    assert {p for p, h in reference['files'].items() if variant['files'][p] != h} == STORE_FILES
    return variant


def build(out, candidate, scan, frontend=False, retain_stream=False, redirect_lookahead=False):
    peer.freeze = lambda source, _: freeze(source, candidate, retain_stream, redirect_lookahead)
    observer = (PEER / 'observe.vh').read_text()
    observer = architecture.augment(observer, HERE.parent / 'thumb_early_load/observe.vh', 'thumb')
    observer = architecture.augment(observer, ARCH / 'observe.vh', 'arch')
    observer = (HERE / 'observe.vh').read_text() + observer
    marker = '        d_walk_start ='
    assert observer.count(marker) == 1
    sample = '        fill_sample();\n'
    if frontend:
        observer = (HERE / 'frontend.vh').read_text() + observer
        sample += '        fill_frontend_sample();\n'
    observer = observer.replace(marker, sample + marker)
    peer.build(out, True, 2, scan, observer.encode())


def build_donor(out, frontend=False):
    out.mkdir(parents=True, exist_ok=False)
    base_harness = donor.harness

    def observed_harness(scan, jpeg):
        tb = base_harness(scan, jpeg)
        observer = (HERE / 'donor.vh').read_text()
        sample = '            donor_sample();\n            fill_sample();'
        if frontend:
            observer += (HERE / 'frontend_donor.vh').read_text()
            sample += '\n            fill_frontend_sample();'
        tb = peer.replace(tb, 'module bench;', 'module bench;\n' + observer)
        return peer.replace(tb, '            donor_sample();', sample)

    donor.harness = observed_harness
    peer.save(out / 'manifest.json', donor.compile_donor(out, False, False))


def replay(out, build_path, stock):
    manifest = json.loads((build_path / 'manifest.json').read_text())
    exe = build_path / 'obj/Vbench'
    assert peer.sha(exe) == manifest['executable' if stock else 'executable_sha256']
    out.mkdir(parents=True, exist_ok=stock and out == build_path)
    case = prepare(out, {'games'})[CASE]
    if stock:
        assert out == build_path
    else:
        case['options'].append('+fill_trace=1')

    def run(profile):
        if not stock:
            return measure(out, exe, manifest, CASE, case, profile, False)
        a = donor.replica(out, case, profile, False, 0)
        b = donor.replica(out, case, profile, False, 1)
        bad = donor.replica(out, case, profile, True, 0)
        assert a == b and bad is None
        return dict(case=CASE, profile=profile, median=a['body_cycles_median'], **a,
                    oracle=case['oracle'], variants=list(case['variants'].values()),
                    repeats_equal=2, wrong_output_rejected=True)

    with ThreadPoolExecutor(max_workers=2) as pool:
        rows = list(pool.map(run, PROFILES))
    peer.save(out / 'result.json', dict(status='PASS', build=manifest, rows=rows))
    for row in rows:
        print('PASS', row['case'], row['profile'], row['median'], 'clocks', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    compile_parser = sub.add_parser('build')
    compile_parser.add_argument('name')
    overlays = compile_parser.add_mutually_exclusive_group()
    overlays.add_argument('--candidate', action='store_true')
    overlays.add_argument('--retain-stream', action='store_true')
    overlays.add_argument('--redirect-lookahead', action='store_true')
    overlays.add_argument('--store-on-lookahead', action='store_true')
    compile_parser.add_argument('--scan', action='store_true')
    compile_parser.add_argument('--frontend', action='store_true')
    donor_parser = sub.add_parser('donor')
    donor_parser.add_argument('name')
    donor_parser.add_argument('--frontend', action='store_true')
    run_parser = sub.add_parser('replay')
    run_parser.add_argument('name')
    run_parser.add_argument('--build', required=True)
    args = parser.parse_args()
    out = peer.OUT / args.name
    if args.command == 'build':
        build(out, args.candidate or args.store_on_lookahead, args.scan, args.frontend,
              args.retain_stream, args.redirect_lookahead or args.store_on_lookahead)
    elif args.command == 'donor':
        build_donor(out, args.frontend)
        replay(out, out, stock=True)
    else:
        replay(out, peer.OUT / args.build, stock=False)


if __name__ == '__main__':
    main()
