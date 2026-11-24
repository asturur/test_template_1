#!/usr/bin/env python3
"""Drive identical ports of the original and candidate execute modules."""
from pathlib import Path
import argparse

from prepare_execute_ready_test import EXECUTE, module, ports


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('reference', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('out', type=Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    original = module(args.reference)
    pins = ports(module(args.candidate))
    assert ports(original) == pins
    (args.out / 'reference.v').write_text(
        original.replace(f'module {EXECUTE} (', 'module reference_execute (', 1))

    declarations = []
    comparisons = []
    for name, (direction, width) in pins.items():
        if direction == 'input':
            declarations.append(f"    reg {width}{name} = '0;")
        else:
            declarations.append(f'    wire {width}reference_{name}, candidate_{name};')
            comparisons.append(
                f'            if (reference_{name} !== candidate_{name}) '
                f'$fatal(1, "changed {name} at clock %0d", clocks);')
    for instance, kind in [('reference', 'reference_execute'), ('candidate', EXECUTE)]:
        declarations.append(f'    {kind} {instance} (')
        declarations.append(',\n'.join(
            f'        .{name}({name if direction == "input" else instance + "_" + name})'
            for name, (direction, _) in pins.items()))
        declarations.append('    );')
    for state in ('accept', 'finish', 'a', 'held', 'held_amount', 'held_rot', 'held_offset',
                  'holding', 'prepared', 's_pending', 's_wait', 'a_wait', 'return_a_match',
                  'multiply_product_ready', 'flags', 'interrupt_mask'):
        comparisons.append(
            f'            if (reference.{state} !== candidate.{state}) '
            f'$fatal(1, "changed {state} at clock %0d", clocks);')
    (args.out / 'shift_ports.vh').write_text('\n'.join(declarations) + '\n')
    (args.out / 'shift_compare.vh').write_text('\n'.join(comparisons) + '\n')


if __name__ == '__main__':
    main()
