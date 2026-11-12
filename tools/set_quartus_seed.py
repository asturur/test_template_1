#!/usr/bin/env python3
"""Select the CI fitter seed, retaining QSF line endings and build provenance."""
import argparse
import json
import os
from pathlib import Path
import re


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('qsf', type=Path)
    parser.add_argument('--seed', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9]{1,10}', args.seed) or not 1 <= int(args.seed) <= 2147483647:
        parser.error('seed must be an integer from1 through2147483647')
    seed = int(args.seed)
    data = args.qsf.read_bytes()
    assignment = re.compile(rb'(?m)^[ \t]*set_global_assignment[ \t]+-name[ \t]+SEED[ \t]+[^\r\n]*')
    matches = list(assignment.finditer(data))
    if len(matches) != 1:
        parser.error('expected exactly one active SEED assignment in QSF')
    args.qsf.write_bytes(assignment.sub(b'set_global_assignment -name SEED ' + str(seed).encode(), data))
    out = Path('output_files/build-info.json')
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(dict(fitter_seed=seed, commit=os.getenv('GITHUB_SHA'),
                                   run_id=os.getenv('GITHUB_RUN_ID'),
                                   timing_status='consult job timing gate and reports'), indent=2) + '\n')
    summary = f'Quartus fitter seed: **{seed}**\n'
    print(summary.strip())
    if os.getenv('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as handle:
            handle.write(summary + '\n')


if __name__ == '__main__':
    main()
