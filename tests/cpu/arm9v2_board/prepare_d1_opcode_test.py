#!/usr/bin/env python3
"""Expose the exact decoder ports for an old/new D1 opcode-class bench."""
import argparse
from pathlib import Path

from prepare_execute_ready_test import ports


DECODER = 'ngage2_arm9v2_decode'


def module(path):
    start = f'module {DECODER} ('
    source = path.read_text()
    assert source.count(start) == 1, path
    return start + source.split(start, 1)[1].split('\nendmodule', 1)[0] + '\nendmodule\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('reference', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    old = module(args.reference)
    interface = ports(old)
    assert interface == ports(module(args.candidate))
    (args.output / 'reference.v').write_text(old.replace(DECODER, 'reference_decode', 1))
    lines = []
    for name, (direction, width) in interface.items():
        decl = f"reg {width}{name} = '0;" if direction == 'input' else f'wire {width}old_{name}, new_{name};'
        lines.append('    ' + decl)
    for instance, typ, prefix in [('reference', 'reference_decode', 'old'), ('candidate', DECODER, 'new')]:
        lines.append(f'    {typ} #(.THUMB_HALF(THUMB_HALF), .PAYLOAD_FREE(PAYLOAD_FREE)) {instance} (')
        lines.append(',\n'.join(
            f'        .{pin}({pin if direction == "input" else f"{prefix}_{pin}"})'
            for pin, (direction, _) in interface.items()
        ))
        lines.append('    );')
    lines.extend(['    task compare_interface;', '        begin'])
    for name, (direction, _) in interface.items():
        if direction == 'output':
            lines.append(f'            if (old_{name} !== new_{name}) $fatal(1, "changed {name} at %0d", clocks);')
    lines.extend(['        end', '    endtask'])
    (args.output / 'interface.vh').write_text('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
