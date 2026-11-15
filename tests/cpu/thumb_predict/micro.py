#!/usr/bin/env python3
"""Measure fixed Thumb BL/BX work with identical binaries on two CPU snapshots."""
import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tests/cpu/donor_import'))
import run as bench


def thumb_cases():
    rows = []
    for name, padding in [('cross', ''), ('same', 'nop')]:
        rows.append(dict(
            id='thumb_calls_' + name, group='B', operations=32,
            asm='''adr r12, thumb_body+1
adr lr, after_thumb
bx r12
.balign 4
.thumb
.thumb_func
thumb_body:
mov r11, lr
''' + padding + '''
.rept 32
bl thumb_leaf
.endr
mov lr, r11
bx lr
.balign 4
.arm
after_thumb:
''',
            tail='''.balign 4
.thumb
.thumb_func
thumb_leaf:
adds r0, #1
bx lr
.balign 4
.arm
''', expected={0: 32}, warmups=2, samples=3))
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name', required=True)
    parser.add_argument('--reference', default='2a04502')
    parser.add_argument('--candidate-alu', type=Path)
    args = parser.parse_args()
    original_cases = bench.cases
    bench.cases = lambda: original_cases() + thumb_cases()
    bench.REFERENCES = {'before': args.reference}
    if args.candidate_alu:
        original_snapshot = bench.snapshot

        def snapshot(destination, revision=None, root=ROOT):
            result = original_snapshot(destination, revision, root)
            if revision is None:
                (destination / 'rtl/arm/zap_alu_main.sv').write_bytes(args.candidate_alu.read_bytes())
                result = bench.source_manifest(destination, result['commit'], 'isolated-thumb-target')
            return result

        bench.snapshot = snapshot
    bench.prepare(argparse.Namespace(name=args.name))
    config = argparse.Namespace(
        name=args.name, variant=['before', 'working'],
        case=[c['id'] for c in thumb_cases()], mode=['line'],
        profile=['0:0', '2:9'], seed=[1], jitter=0, jobs=3)
    for repeat in range(2):
        assert bench.run(config) == 0
    out = ROOT / 'build/sim/cpu-donor-import' / args.name
    results = [json.loads((p / 'result.json').read_text())
               for p in sorted((out / 'attempts').iterdir())]
    assert len(results) == 2 and all(r['status'] == 'PASS' for r in results)
    clean = lambda r: [{k: v for k, v in x.items() if k != 'log'} for x in r['rows']]
    assert clean(results[0]) == clean(results[1]), 'repeats differ'
    comparison = bench.compare_rows(results[0]['rows'], 'before', 'working')
    assert len(comparison) == 4
    report = dict(status='PASS', repeats=2, comparison=comparison, rows=results[0]['rows'])
    (out / 'thumb-comparison.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(comparison, indent=2))


if __name__ == '__main__':
    main()
