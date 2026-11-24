#!/usr/bin/env python3
"""Create identical-pin execute instances with independent issue enables."""
import argparse
from pathlib import Path

from prepare_execute_ready_test import EXECUTE, module, ports


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('reference', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    old = module(args.reference)
    pins = ports(module(args.candidate))
    assert pins == ports(old)
    (args.output/'reference.v').write_text(
        old.replace(f'module {EXECUTE} (', 'module reference_execute (', 1))

    declarations = ["    reg reference_i_valid = 0, candidate_i_valid = 0;"]
    for pin, (direction, width) in pins.items():
        if pin == 'i_valid':
            continue
        if direction == 'input':
            declarations.append(f"    reg {width}{pin} = '0;")
        else:
            declarations.append(f'    wire {width}reference_{pin}, candidate_{pin};')
    for name, kind in [('reference', 'reference_execute'), ('candidate', EXECUTE)]:
        declarations.append(f'    {kind} {name} (')
        declarations.append(',\n'.join(
            f'        .{pin}({name + "_" + pin if direction == "output" or pin == "i_valid" else pin})'
            for pin, (direction, _) in pins.items()))
        declarations.append('    );')
    (args.output/'wb_rs_ports.vh').write_text('\n'.join(declarations)+'\n')


if __name__ == '__main__':
    main()
