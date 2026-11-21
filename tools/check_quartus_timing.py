#!/usr/bin/env python3
"""Reject failed/incomplete TimeQuest reports even when Quartus exits zero.

This checks reported constrained timing. It does not certify unconstrained
external interfaces; those remain visible in the detailed report artifact.
"""
import argparse
import csv
from decimal import Decimal
import json
from pathlib import Path
import re

REQUIRED = {'setup', 'hold', 'recovery', 'removal', 'minimum pulse width'}
SLACK = re.compile(r'^Info \(332146\): Worst-case ([a-z ]+) slack is (-?\d+(?:\.\d+)?)\s*$', re.M)
CORNER_SLACK = re.compile(r'^Report .* Worst case slack is (-?\d+(?:\.\d+)?)\s*$', re.M)
CORNER_REPORTS = ('setup', 'hold', 'recovery', 'removal', 'min-pulse')

def check(report):
    if 'Timing requirements not met' in report:
        raise ValueError('Quartus reports Timing requirements not met')
    observed = {}
    for name, value in SLACK.findall(report):
        if name in REQUIRED:
            number = Decimal(value)
            observed[name] = min(observed.get(name, number), number)
    missing = REQUIRED - observed.keys()
    if missing:
        raise ValueError('missing timing results: ' + ', '.join(sorted(missing)))
    failed = [f'{name}={value} ns' for name, value in observed.items() if value < 0]
    if failed:
        raise ValueError('negative timing slack: ' + ', '.join(failed))
    return observed


def check_native_corners(root, manifest):
    expected_mhz = json.loads(manifest.read_text())['physical_cpu_mhz']
    clock = dict(line.split('=', 1) for line in (root / 'physical-clock.txt').read_text().splitlines())
    if expected_mhz != int(clock['physical_mhz']):
        raise ValueError('Fitted core clock disagrees with selected PLL source')
    if abs(Decimal(clock['period_ns']) - Decimal(1000) / expected_mhz) > Decimal('0.002'):
        raise ValueError('Native core period disagrees with selected PLL source')
    scenario = root / str(expected_mhz)
    if 'physical fitted PLL' not in (scenario / 'clock-coverage-PASS.txt').read_text():
        raise ValueError('Selected timing scenario is not labeled as the physical PLL')

    expected_conditions = {(model, temperature) for model in ('slow', 'fast') for temperature in ('100', '-40')}
    conditions = set()
    for corner in sorted(scenario.glob('corner-*')):
        fields = dict(line.split(': ', 1) for line in (corner / 'operating-condition.txt').read_text().splitlines())
        condition = (fields['model'], fields['temperature'])
        if condition not in expected_conditions or condition in conditions:
            raise ValueError(f'Unexpected or duplicate native operating condition {condition}')
        conditions.add(condition)
        with (corner / 'setup.csv').open(newline='') as handle:
            paths = list(csv.DictReader(handle))
        if len(paths) != 1000 or any(row['rank'] != str(n) or not row['from'] or not row['to']
                                     for n, row in enumerate(paths, 1)):
            raise ValueError(f'{corner}: expected 1000 ranked setup paths')
        values = {}
        for kind in CORNER_REPORTS:
            match = CORNER_SLACK.search((corner / f'{kind}.rpt').read_text())
            if not match:
                raise ValueError(f'{corner}: missing {kind} slack')
            values[kind] = Decimal(match[1])
        yield corner.name, condition, values
    if conditions != expected_conditions:
        raise ValueError(f'missing native operating conditions {expected_conditions - conditions}')

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('report', type=Path)
    p.add_argument('--native-corners', type=Path)
    p.add_argument('--fit-manifest', type=Path)
    a = p.parse_args()
    if bool(a.native_corners) != bool(a.fit_manifest):
        p.error('--native-corners and --fit-manifest are required together')
    try:
        if a.native_corners:
            failed = []
            for name, condition, slacks in check_native_corners(a.native_corners, a.fit_manifest):
                label = f'{name} {condition[0]} {condition[1]}C'
                print(f'Native {label}: ' + ', '.join(f'{kind}={value} ns' for kind, value in slacks.items()))
                failed.extend(f'{label} {kind}={value} ns' for kind, value in slacks.items() if value < 0)
            if failed:
                raise ValueError('negative native timing slack: ' + ', '.join(failed))
        values = check(a.report.read_text())
    except (OSError, ValueError, KeyError) as e:
        p.exit(1, f'Timing gate FAILED: {e}\n')
    print('PASS constrained setup/hold/recovery/removal/pulse-width timing: ' +
          ', '.join(f'{name}={values[name]} ns' for name in sorted(values)))

if __name__ == '__main__':
    main()
