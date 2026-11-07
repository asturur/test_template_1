#!/usr/bin/env python3
"""Reject failed/incomplete TimeQuest reports even when Quartus exits zero.

This checks reported constrained timing. It does not certify unconstrained
external interfaces; those remain visible in the detailed report artifact.
"""
import argparse
from decimal import Decimal
from pathlib import Path
import re

REQUIRED = {'setup', 'hold', 'recovery', 'removal', 'minimum pulse width'}
SLACK = re.compile(r'^Info \(332146\): Worst-case ([a-z ]+) slack is (-?\d+(?:\.\d+)?)\s*$', re.M)

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

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('report', type=Path)
    a = p.parse_args()
    try:
        values = check(a.report.read_text())
    except (OSError, ValueError) as e:
        p.exit(1, f'Timing gate FAILED: {e}\n')
    print('PASS constrained setup/hold/recovery/removal/pulse-width timing: ' +
          ', '.join(f'{name}={values[name]} ns' for name in sorted(values)))

if __name__ == '__main__':
    main()
