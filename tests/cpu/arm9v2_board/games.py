#!/usr/bin/env python3
"""Run the original checked game loops on the three frozen SPMark binaries."""

import argparse
import json
from pathlib import Path
import re
import struct
import subprocess
import sys

import game
import monkey

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tests/cpu/spmark_payload'))
import run as bench
from workloads import assembly


def build_guest(out, name, source, payload):
    files = {suffix: out / (name + suffix) for suffix in ('.S', '.o', '.elf', '.bin')}
    files['.S'].write_text(source)
    commands = (
        ['arm-none-eabi-gcc', '-c', '-mcpu=arm920t', '-marm', files['.S'], '-o', files['.o']],
        ['arm-none-eabi-ld', '-T', ROOT / 'sim/programs/link.ld', files['.o'], '-o', files['.elf']],
        ['arm-none-eabi-objcopy', '-O', 'binary', files['.elf'], files['.bin']],
    )
    for index, command in enumerate(commands):
        bench.command(command, out / f'{name}-guest-{index}.log')
    table = subprocess.check_output(['arm-none-eabi-nm', files['.elf']], text=True)
    symbols = {parts[2]: int(parts[0], 16) for line in table.splitlines()
               if len(parts := line.split()) == 3}
    raw = files['.bin'].read_bytes()
    assert len(raw) < 0x40000
    code = payload(symbols)
    bench.hexfile(out / f'{name}.hex', raw)
    bench.hexfile(out / f'{name}-payload.hex', code)
    return dict(name=name, program_sha256=bench.sha(raw), payload_sha256=bench.sha(code),
                begin_pc=symbols['body_begin'], end_pc=symbols['body_end'])


def prepare(out, fixtures):
    cases = []
    code = monkey.extract(fixtures / 'super_monkey_ball/local/SuperMonkeyBall.app')
    for pattern in ('forward', 'reverse'):
        case = dict(id='monkey-' + pattern, operations=monkey.PIXELS, unit='pixels', warmups=2, samples=5)
        inputs = monkey.fixture(pattern)
        oracle = monkey.oracle(code, inputs)
        variants = []
        for bad in (False, True):
            source = monkey.assembly(inputs, bad)
            source = source.replace(' mov lr,pc\n bx r12', '''
.global body_begin
body_begin:
 nop
 mov lr,pc
 bx r12
.global body_end
body_end:
 nop''')
            variants.append(build_guest(out, case['id'] + ('-wrong' if bad else ''), source,
                                        lambda _symbols: bytes(monkey.ENTRY) + code + struct.pack('<I', 0xe12fff1e)))
        cases.append((case, oracle, variants))

    originals = {name: game.image(name, fixtures) for name in game.IMAGES}
    for name, (title, entry, last) in game.LOOPS.items():
        case = game.fixture(name)
        code = originals[title][entry:last + 4]
        oracle = game.verify(case, code, entry, last)
        variants = []
        for bad in (False, True):
            source = game.assembly(case, entry, bad, assembly)
            variants.append(build_guest(out, name + ('-wrong' if bad else ''), source,
                                        lambda symbols: bytes(entry) + code + struct.pack('<II', 0xe51ff004, symbols['loop_return'])))
        cases.append((case, oracle, variants))
    return cases


def measure(out, binary, case, oracle, variants, cpu, profile):
    iw, dw = profile.split(':')
    docker = ['docker', 'run', '--rm', '--pull=never', '--network', 'none', '--platform', 'linux/arm64',
              '-v', str(ROOT) + ':/work', '-w', '/work', '--entrypoint', bench.cpath(binary), bench.IMAGE]
    rows = []
    for variant, repeats in zip(variants, (2, 1)):
        bad = variant is variants[1]
        name = variant['name']
        for repeat in range(repeats):
            log = out / f'{cpu}-{name}-{iw}-{dw}-{repeat}.log'
            flags = [f'+program={bench.cpath(out / (name + ".hex"))}',
                     f'+payload={bench.cpath(out / (name + "-payload.hex"))}',
                     f'+firmware={bench.cpath(out / "empty.hex")}',
                     f'+begin_pc={variant["begin_pc"]:x}', f'+end_pc={variant["end_pc"]:x}',
                     f'+i_wait={iw}', f'+d_wait={dw}', '+max_cycles=30000000', '+ngage-compact-trace']
            try:
                bench.command(docker + flags, log)
            except RuntimeError:
                if bad and 'guest result check failed' in log.read_text():
                    continue
                raise
            if bad:
                raise ValueError(f'Wrong output passed {log}')
            log_text = log.read_text()
            windows = bench.support().parse_log(log_text, case)
            retired = [tuple(map(int, re.findall(r'=(\d+)', line)))
                       for line in log_text.splitlines() if line.startswith('PAYLOAD_WINDOW ')]
            assert retired == [(i, oracle['instructions'] + 1, 0) for i in range(7)], (log, retired)
            windows['traffic'] = [dict(re.findall(r'(\w+)=(\d+)', line)) for line in log_text.splitlines()
                                  if line.startswith('TRAFFIC ')]
            assert len(windows['traffic']) == 7
            rows.append(windows)
    assert rows[0] == rows[1], 'Identical repeats differ'
    return dict(cpu=cpu, case=case['id'], profile=profile, operations=case['operations'],
                oracle=oracle, guest=variants[0], wrong_output_rejected=True, repeats=2, **rows[0])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixtures', required=True, type=Path, help='Read-only directory containing the three local game fixtures')
    parser.add_argument('--name', required=True)
    parser.add_argument('--leg', action='append', required=True, metavar='CPU=SPMARK_RUN')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,63}', args.name):
        parser.error('Invalid run name')
    out = ROOT / 'build/sim/arm9v2' / args.name
    out.mkdir(parents=True)
    result = dict(status='INCOMPLETE', sources={}, rows=[])
    bench.save(out / 'result.json', result)
    bench.hexfile(out / 'empty.hex', bytes(4))
    cases = prepare(out, args.fixtures)
    for leg in args.leg:
        cpu, name = leg.split('=', 1)
        folder = ROOT / 'build/sim/spmark-payload' / name
        summary = json.loads((folder / 'result.json').read_text())
        assert summary['status'] == 'PASS' and summary['comparison_cpu'] == cpu
        manifest = summary['manifest']
        binary = ROOT / manifest['executable']
        assert manifest['executable_sha256'] == bench.sha(binary.read_bytes())
        result['sources'][cpu] = manifest
        for case, oracle, variants in cases:
            for profile in ('0:0', '2:9'):
                row = measure(out, binary, case, oracle, variants, cpu, profile)
                result['rows'].append(row)
                print(cpu, case['id'], profile, row['body_cycles_median'], 'cycles', flush=True)
                bench.save(out / 'result.json', result)
    result['status'] = 'PASS'
    bench.save(out / 'result.json', result)


if __name__ == '__main__':
    main()
