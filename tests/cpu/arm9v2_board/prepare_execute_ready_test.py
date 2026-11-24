#!/usr/bin/env python3
"""Build a differential bench around the actual old and new execute modules."""
import argparse
from pathlib import Path
import re


EXECUTE = 'ngage2_arm9v2_execute'
HIT_PORTS = {'i_load_wait_hit', 'i_load_wait_nohit'}
PORT = re.compile(
    r'^\s*(?:\(\*[^\n]*\*\)\s*)?(input|output) (?:wire|reg) (?:signed )?'
    r'(\[\d+:0\] )?(\w+);$',
    re.M,
)


def module(path):
    start = f'module {EXECUTE} ('
    text = path.read_text()
    assert text.count(start) == 1, path
    return start + text.split(start, 1)[1].split('\nendmodule', 1)[0] + '\nendmodule\n'


def ports(text):
    header = text.split('(', 1)[1].split(');', 1)[0]
    names = {name.strip() for name in header.split(',')}
    result = {}
    for direction, width, name in PORT.findall(text):
        if name in names:
            assert name not in result, name
            result[name] = (direction, width)
    assert result.keys() == names
    return result


def connection(instance, name, candidate_ports):
    direction, _ = candidate_ports[name]
    if direction == 'output':
        return f'{instance}_{name}'
    if instance == 'reference' and name == 'i_load_wait':
        return 'i_load_wait || (i_load_hit ? i_load_wait_hit : i_load_wait_nohit)'
    return name


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('reference', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('out', type=Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    old = module(args.reference)
    new_ports = ports(module(args.candidate))
    old_ports = ports(old)
    assert new_ports.keys() - old_ports.keys() == HIT_PORTS
    assert all(new_ports[k] == v for k, v in old_ports.items())
    (args.out / 'reference.v').write_text(
        old.replace(f'module {EXECUTE} (', 'module reference_execute (', 1))
    out = [
        '`timescale 1ns/1ps',
        'module execute_ready_tb;',
        '    integer n;',
        '    integer seed = 32\'h5224d9a8;',
        '    integer accepted = 0, held = 0, replaced = 0, hit_released = 0, prepared = 0;',
        '    integer w_blocked = 0, m_priority = 0, flushes = 0, redirects = 0;',
    ]
    for name, (direction, width) in new_ports.items():
        if direction == 'input':
            out.append(f"    reg {width}{name} = '0;")
        else:
            out.append(f'    wire {width}reference_{name}, candidate_{name};')
    for name, typ, interface in [
        ('reference', 'reference_execute', old_ports),
        ('candidate', EXECUTE, new_ports),
    ]:
        out.append(f'    {typ} {name} (')
        out.append(',\n'.join(
            f'        .{pin}({connection(name, pin, new_ports)})' for pin in interface))
        out.append('    );')

    out += [
        '    task compare;',
        '        begin',
    ]
    for pin, (direction, _) in new_ports.items():
        if direction == 'output':
            out.append(f'            if (reference_{pin} !== candidate_{pin}) '
                       f'$fatal(1, "changed {pin} at iteration %0d", n);')
    for register in ('a', 'held', 'held_amount', 'held_rot', 'held_offset',
                     'prepared', 'holding', 's_pending', 's_wait', 'a_wait',
                     'a_wait_nohit', 'accept', 'finish'):
        out.append(f'            if (reference.{register} !== candidate.{register}) '
                   f'$fatal(1, "changed {register} at iteration %0d", n);')
    out += [
        '        end',
        '    endtask',
        '    initial begin',
        '        i_reset = 1;',
        '        #5 i_clk = 1;',
        '        #5 i_clk = 0;',
        '        for (n = 0; n < 20000; n = n + 1) begin',
    ]
    controlled = {'i_clk', 'i_reset', 'i_flush', 'i_kind', 'i_valid',
                  'i_ready', 'i_admit', 'i_load_wait'}
    for pin, (direction, _) in new_ports.items():
        if direction == 'input' and pin not in controlled:
            # Four draws provide real entropy for all 128-bit operands.
            values = ', '.join('$random(seed)' for _ in range(4))
            out.append(f'            {pin} = {{{values}}};')
    out += [
        '            i_reset = n % 97 == 0;',
        '            i_flush = n % 61 == 0;',
        '            i_valid = n % 5 != 0;',
        '            i_ready = n % 7 != 0;',
        '            i_admit = n % 11 != 0;',
        '            i_load_wait = n % 13 == 0;',
        '            i_kind = n % 14;',
        '            #4;',
        '            compare();',
        '            if (candidate.accept) accepted++;',
        '            if (candidate.holding) held++;',
        '            if (candidate.accept && candidate.finish) replaced++;',
        '            if (candidate.accept && !candidate.ready_if_nohit) hit_released++;',
        '            if (candidate.prepared) prepared++;',
        '            if (!i_load_hit && candidate.ready_if_hit && !candidate.ready_if_nohit) w_blocked++;',
        '            if ((|i_forward_match[1:0]) && (|i_forward_match[3:2]) && i_load_owner[1]) m_priority++;',
        '            if (i_flush) flushes++;',
        '            if (candidate_o_redirect) redirects++;',
        '            #1 i_clk = 1;',
        '            #4 compare();',
        '            #1 i_clk = 0;',
        '        end',
        '        if (!(accepted && held && replaced && hit_released && prepared && w_blocked &&',
        '              m_priority && flushes && redirects)) $fatal(1, "missing readiness coverage");',
        '        $display("PASS execute readiness %0d cycles accepted=%0d held=%0d replaced=%0d hit_release=%0d prepared=%0d w_blocked=%0d m_priority=%0d flushes=%0d redirects=%0d",',
        '                 n, accepted, held, replaced, hit_released, prepared, w_blocked, m_priority, flushes, redirects);',
        '        $finish;',
        '    end',
        'endmodule',
    ]
    (args.out / 'tb.sv').write_text('\n'.join(out) + '\n')


if __name__ == '__main__':
    main()
