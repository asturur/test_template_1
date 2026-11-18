#!/usr/bin/env python3
"""Run the original checked game loops on the three frozen SPMark binaries."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import re
import struct
import subprocess
import sys

import game
import monkey
import sega_scan

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tests/cpu/spmark_payload'))
import run as bench
from workloads import ROM_SHA, assembly


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


def prepare_scan(out, fixtures):
    rom = (ROOT / 'build/firmware/nem4-factory/core.bin').read_bytes()
    assert bench.sha(rom) == ROM_SHA
    case, code = sega_scan.fixture(rom, fixtures)
    firmware = rom[0x500000:0x600000]
    case['firmware'] = 'sega-fbs.hex'
    bench.hexfile(out / case['firmware'], firmware)
    oracle = sega_scan.verify(case, code, firmware)
    return [(case, oracle, [
        build_guest(out, case['id'] + ('-wrong' if bad else ''),
                    sega_scan.assembly(case, bad, assembly), lambda symbols: sega_scan.payload(code, symbols))
        for bad in (False, True)
    ])]


def compile_scan(out, folder, cpu, manifest):
    # Disjoint 73 KiB guarded buffers require 256 KiB of mapped RAM. Translate
    # FbsCli virtual PCs for the oracle while leaving the firmware PA unchanged.
    text = (folder / 'tb.v').read_text()
    assert bench.sha(text.encode()) == manifest['harness_sha256']
    text = text.replace('ram[0:32767]', 'ram[0:65535]').replace('n<32768', 'n<65536')
    text = text.replace("32'h0a020000", "32'h0a040000").replace('[16:2]', '[17:2]')
    text = text.replace("if(retire_pc>=32'h50300000 && retire_pc<32'h50400000)",
                        "if(retire_pc>=32'h50500000 && retire_pc<32'h50600000)")
    target = out / cpu
    target.mkdir()
    (target / 'tb.v').write_text(text)
    source = folder / 'source'
    files = manifest['source']['files']
    docker = ['docker', 'run', '--rm', '--pull=never', '--network', 'none', '--platform', 'linux/arm64',
              '-v', str(ROOT) + ':/work']
    flags = ['-I' + bench.cpath(source / 'rtl/arm')]
    if cpu == 'ngage2':
        dependencies = manifest['source']['dependencies']
        donor = Path(manifest['source']['dependency_root'])
        assert all(bench.sha((donor / p).read_bytes()) == sha for p, sha in dependencies.items())
        docker += ['-v', str(donor) + ':/donor:ro']
        rtl = ['/donor/' + p for p in ('rtl/cpu/arm925t_gen.v', 'sim/stubs/altsyncram.sv', 'sim/stubs/altdpram.sv')]
    else:
        assert all(bench.sha((source / p).read_bytes()) == sha for p, sha in files.items())
        rtl = [bench.cpath(source / p) for p in sorted(files) if p.endswith(('.v', '.sv'))]
        if cpu == 'arm9v2':
            flags.append('-DNGAGE_ARM9V2')
    obj = target / 'obj'
    bench.command(docker + ['-w', '/work', '--entrypoint', 'verilator', bench.IMAGE, '--binary', '--timing',
                            '--assert', '-j', '2', '-Wno-fatal', '-Wno-lint', '-DNGAGE_RUNTIME_TRACE',
                            '-DBENCH_HAS_LINE', '-GLINE_ENABLE=1', '--top-module', 'bench', '--Mdir', bench.cpath(obj)] +
                  flags + rtl + [bench.cpath(target / 'tb.v')], target / 'build.log')
    return obj / 'Vbench'


def attempt(out, docker, case, oracle, variant, cpu, profile, bad, repeat):
    iw, dw = profile.split(':')
    name = variant['name']
    log = out / f'{cpu}-{name}-{iw}-{dw}-{repeat}.log'
    flags = [f'+program={bench.cpath(out / (name + ".hex"))}',
             f'+payload={bench.cpath(out / (name + "-payload.hex"))}',
             f'+firmware={bench.cpath(out / case.get("firmware", "empty.hex"))}',
             f'+begin_pc={variant["begin_pc"]:x}', f'+end_pc={variant["end_pc"]:x}',
             f'+i_wait={iw}', f'+d_wait={dw}', '+max_cycles=90000000', '+ngage-compact-trace']
    try:
        bench.command(docker + flags, log)
    except RuntimeError:
        if bad and 'guest result check failed' in log.read_text():
            return None
        raise
    if bad:
        raise ValueError(f'Wrong output passed {log}')
    log_text = log.read_text()
    windows = bench.support().parse_log(log_text, case)
    retired = [tuple(map(int, re.findall(r'=(\d+)', line)))
               for line in log_text.splitlines() if line.startswith('PAYLOAD_WINDOW ')]
    original = oracle.get('payload_instructions', oracle.get('instructions'))
    helpers = oracle.get('helper_instructions', 0)
    if cpu != 'base':
        helpers += sum(oracle.get('thumb_bl_suffixes', {}).values())
    assert retired == [(i, original + 1, helpers) for i in range(7)], (log, retired)
    windows['traffic'] = [dict(re.findall(r'(\w+)=(\d+)', line)) for line in log_text.splitlines()
                          if line.startswith('TRAFFIC ')]
    assert len(windows['traffic']) == 7
    return windows


def measure(out, binary, case, oracle, variants, cpu, workers):
    docker = ['docker', 'run', '--rm', '--pull=never', '--network', 'none', '--platform', 'linux/arm64',
              '-v', str(ROOT) + ':/work', '-w', '/work', '--entrypoint', bench.cpath(binary), bench.IMAGE]
    with ThreadPoolExecutor(max_workers=workers) as pool:
        tasks = {profile: [pool.submit(attempt, out, docker, case, oracle, variants[bad], cpu, profile, bad, repeat)
                           for bad, repeat in ((False, 0), (False, 1), (True, 0))]
                 for profile in ('0:0', '2:9')}
        for profile, results in tasks.items():
            first, repeat, negative = (job.result() for job in results)
            assert first == repeat and negative is None, 'Repeated runs or the negative control differ'
            yield dict(cpu=cpu, case=case['id'], profile=profile, operations=case['operations'],
                       oracle=oracle, guest=variants[0], wrong_output_rejected=True, repeats=2, **first)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixtures', required=True, type=Path, help='Read-only directory containing the three local game fixtures')
    parser.add_argument('--name', required=True)
    parser.add_argument('--leg', action='append', required=True, metavar='CPU=SPMARK_RUN')
    parser.add_argument('--workers', type=int, choices=range(1, 7), default=1, help='Parallel simulation processes per case')
    parser.add_argument('--sega-scan-only', action='store_true', help='Run the full-screen Sega Rally scan with its native FbsCli calls')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,63}', args.name):
        parser.error('Invalid run name')
    out = ROOT / 'build/sim/arm9v2' / args.name
    out.mkdir(parents=True)
    result = dict(status='INCOMPLETE', sources={}, rows=[])
    bench.save(out / 'result.json', result)
    bench.hexfile(out / 'empty.hex', bytes(4))
    cases = prepare_scan(out, args.fixtures) if args.sega_scan_only else prepare(out, args.fixtures)
    for leg in args.leg:
        cpu, name = leg.split('=', 1)
        folder = ROOT / 'build/sim/spmark-payload' / name
        summary = json.loads((folder / 'result.json').read_text())
        assert summary['status'] == 'PASS' and summary['comparison_cpu'] == cpu
        manifest = summary['manifest']
        binary = ROOT / manifest['executable']
        assert manifest['executable_sha256'] == bench.sha(binary.read_bytes())
        result['sources'][cpu] = dict(manifest)
        if args.sega_scan_only:
            binary = compile_scan(out, folder, cpu, manifest)
            result['sources'][cpu]['scan_executable_sha256'] = bench.sha(binary.read_bytes())
            result['sources'][cpu]['scan_harness_sha256'] = bench.sha((out / cpu / 'tb.v').read_bytes())
        for case, oracle, variants in cases:
            for row in measure(out, binary, case, oracle, variants, cpu, args.workers):
                result['rows'].append(row)
                print(cpu, case['id'], row['profile'], row['body_cycles_median'], 'cycles', flush=True)
                bench.save(out / 'result.json', result)
    result['status'] = 'PASS'
    bench.save(out / 'result.json', result)


if __name__ == '__main__':
    main()
