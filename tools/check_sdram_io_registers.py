#!/usr/bin/env python3
"""Require all 16 SDRAM DQ pins to use input, output and OE I/O registers."""
import argparse
import re
from pathlib import Path


def check_report(path):
    columns = None
    pins = {}
    required = ('Input Register', 'Output Register', 'Output Enable Register')
    for line in path.read_text(errors='replace').splitlines():
        if not line.startswith(';'):
            continue
        fields = [field.strip() for field in line.split(';')[1:-1]]
        if all(name in fields for name in ('Name', 'Pin #', *required)):
            columns = {name: fields.index(name) for name in ('Name', *required)}
            continue
        if columns is None or len(fields) <= max(columns.values()):
            continue
        match = re.fullmatch(r'SDRAM_DQ\[(\d+)\]', fields[columns['Name']])
        if match:
            index = int(match[1])
            if index in pins:
                raise ValueError(f'duplicate SDRAM_DQ[{index}] I/O table row')
            pins[index] = {name: fields[columns[name]].lower() for name in required}
            if len(pins) == 16:
                break
    if set(pins) != set(range(16)):
        raise ValueError(f'expected 16 SDRAM DQ I/O rows; found {sorted(pins)}')
    failures = [f'SDRAM_DQ[{index}]: {name}={value}'
                for index, fields in sorted(pins.items())
                for name, value in fields.items() if value != 'yes']
    if failures:
        raise ValueError('\n'.join(failures))
    print('PASS all 16 SDRAM DQ input/output/OE registers are packed in I/O cells')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path, help='Quartus .fit.rpt file')
    args = parser.parse_args()
    try:
        check_report(args.report)
    except (OSError, ValueError) as error:
        parser.exit(1, f'FAIL SDRAM I/O registers: {error}\n')


if __name__ == '__main__':
    main()
