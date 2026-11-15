#!/usr/bin/env python3
"""Select the complete DDR runtime recorder at compile time and record it."""
import argparse
import json
import os
from pathlib import Path
import re


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('qsf', type=Path)
    parser.add_argument('--enabled', required=True, choices=('true', 'false'))
    parser.add_argument('--metadata', type=Path, default=Path('output_files/build-info.json'))
    args = parser.parse_args()
    enabled = args.enabled == 'true'
    data = args.qsf.read_bytes()
    # Touch only this macro. Preserve other macros, comments and line endings.
    macro = re.compile(rb'(?m)^[ \t]*set_global_assignment[ \t]+-name[ \t]+VERILOG_MACRO[ \t]+"?ENABLE_DEBUGGER(?:=[01])?"?[ \t]*(?:\r?\n|$)')
    data = macro.sub(b'', data)
    newline = b'\r\n' if b'\r\n' in data else b'\n'
    if data and not data.endswith(b'\n'):
        data += newline
    data += b'set_global_assignment -name VERILOG_MACRO "ENABLE_DEBUGGER=' + (b'1' if enabled else b'0') + b'"' + newline
    args.qsf.write_bytes(data)
    info = json.loads(args.metadata.read_text()) if args.metadata.exists() else {}
    info['enable_debugger'] = enabled
    info['debugger_macro'] = 'ENABLE_DEBUGGER=' + str(int(enabled))
    args.metadata.parent.mkdir(parents=True, exist_ok=True)
    args.metadata.write_text(json.dumps(info, indent=2) + '\n')
    summary = 'DDR runtime debugger: **' + ('enabled' if enabled else 'compiled out') + '**\n'
    print(summary.strip())
    if os.getenv('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as handle:
            handle.write(summary + '\n')


if __name__ == '__main__':
    main()
