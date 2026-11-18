#!/usr/bin/env python3
"""Step 5I: original private span bytes, exact accepted 5F, offline serial replay."""
import argparse
import importlib.util
import json
import re
import shutil
import statistics
import struct
import subprocess
import sys
from pathlib import Path

from workload import (BASE, ENTRY, EXIT, PIXELS, SHA, assembly, digest, extract, fixture, oracle)

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
REVISION = '8e70b1ebc16486443d09f008384b4c0bc41c071c'
IMAGE = 'jotego/simulator:arm64'


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def hexfile(path, value):
    value += bytes(-len(value) % 4)
    path.write_text(''.join(f'{v[0]:08x}\n' for v in struct.iter_unpack('<I', value)))


def cpath(path):
    return '/work/' + str(path.relative_to(ROOT))


def command(args, log, allow_failure=False):
    with log.open('w') as f:
        f.write(json.dumps([str(a) for a in args]) + '\n')
        f.flush()
        result = subprocess.run([str(a) for a in args], cwd=ROOT, stdout=f, stderr=subprocess.STDOUT)
    if result.returncode and not allow_failure:
        raise RuntimeError(f'command failed: {log}')
    return result.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name', required=True)
    parser.add_argument('--app', type=Path, default=HERE/'local/SuperMonkeyBall.app')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,63}', args.name):
        parser.error('invalid new run name')
    out = ROOT/'build/sim/super-monkey-ball'/args.name
    out.mkdir(parents=True, exist_ok=False)
    save(out/'result.json', dict(status='INCOMPLETE'))
    code = extract(args.app)
    fixtures = {p: fixture(p) for p in ['forward', 'reverse']}
    oracles = {p: oracle(code, f) for p, f in fixtures.items()}
    save(out/'oracle.json', oracles)
    print('PASS original SHA, independent reference, Unicorn, pixel/guard negative controls', flush=True)
    # Reuse the maintained CPU source freezer, not any donor RTL or donor job.
    sys.path.insert(0, str(ROOT/'tests/cpu/donor_import'))
    spec = importlib.util.spec_from_file_location('cpu_support', ROOT/'tests/cpu/donor_import/run.py')
    support = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(support)
    source = support.snapshot(out/'source', REVISION)
    tb = (ROOT/'tests/cpu/spmark_payload/tb.v').read_text()
    tb = tb.replace('module bench;', 'module bench;\n`include "observe.vh"')
    start = tb.index('            if(retire && retire_pc==begin_pc) begin')
    end = tb.index('            if(line_req&&line_ready) begin', start)
    tb = tb[:start] + '            span_sample();\n' + tb[end:]
    start = tb.index('        if(!$value$plusargs("begin_pc=')
    end = tb.index('        if(!$value$plusargs("i_wait=', start)
    tb = tb[:start] + '        if(!$value$plusargs("span_trace=%d",trace_enable))trace_enable=0;\n' + tb[end:]
    (out/'tb.v').write_text(tb)
    shutil.copyfile(HERE/'observe.vh', out/'observe.vh')
    # Keep only the exact original 80 bytes at their preferred offsets. An
    # explicit ARMv4 BX LR exit shim follows, outside the extracted loop.
    payload = bytes(ENTRY) + code + struct.pack('<I', 0xe12fff1e)
    hexfile(out/'payload.hex', payload)
    hexfile(out/'firmware.hex', bytes(4))
    programs = {}
    for pattern, f in fixtures.items():
        for bad in [False, True]:
            name = pattern + ('-wrong' if bad else '')
            path = out/name
            path.with_suffix('.S').write_text(assembly(f, bad))
            command(['arm-none-eabi-gcc', '-c', '-mcpu=arm920t', '-marm', path.with_suffix('.S'), '-o', path.with_suffix('.o')], out/(name+'.assemble.log'))
            command(['arm-none-eabi-ld', '-T', ROOT/'sim/programs/link.ld', path.with_suffix('.o'), '-o', path.with_suffix('.elf')], out/(name+'.link.log'))
            command(['arm-none-eabi-objcopy', '-O', 'binary', path.with_suffix('.elf'), path.with_suffix('.bin')], out/(name+'.objcopy.log'))
            raw = path.with_suffix('.bin').read_bytes()
            assert len(raw) < 0x40000
            hexfile(path.with_suffix('.hex'), raw)
            programs[name] = digest(raw)
    image_id = subprocess.check_output(['docker', 'image', 'inspect', IMAGE, '--format', '{{.Id}}']).decode().strip()
    manifest = dict(revision=REVISION, source=source, image_id=image_id, app_sha256=SHA,
                    loop_sha256=digest(code), original_bytes=len(code), programs=programs,
                    harness_sha256=digest(tb.encode()),
                    observer_sha256=digest((out/'observe.vh').read_bytes()),
                    input_generator_sha256=digest((HERE/'workload.py').read_bytes()),
                    runner_sha256=digest(Path(__file__).read_bytes()),
                    pixels=PIXELS, warmups=2, samples=5, repeats=2,
                    boundary='first loop operand_pop edge to final original BLT retirement edge; delta end-start')
    save(out/'manifest.json', manifest)
    docker = ['docker', 'run', '--rm', '--pull=never', '--network', 'none', '--platform', 'linux/arm64',
              '-v', str(ROOT)+':/work', '-w', '/work', '--entrypoint']
    rtl = [out/'source/rtl/ngage_cpu.sv', out/'source/rtl/ngage_bram.v']
    for directory in ['rtl/arm', 'rtl/arm920']:
        rtl += sorted(p for p in (out/'source'/directory).iterdir() if p.suffix in ('.v', '.sv'))
    command(docker + ['verilator', IMAGE, '--binary', '--timing', '--assert', '-j', '1',
                     '-Wno-fatal', '-Wno-lint', '-DNGAGE_RUNTIME_TRACE', '-DBENCH_HAS_LINE',
                     '-GLINE_ENABLE=1', '--top-module', 'bench', '--Mdir', cpath(out/'obj'),
                     '-I'+cpath(out), '-I'+cpath(out/'source/rtl/arm')] +
            [cpath(p) for p in rtl] + [cpath(out/'tb.v')], out/'build.log')
    executable = out/'obj/Vbench'
    manifest['executable_sha256'] = digest(executable.read_bytes())
    save(out/'manifest.json', manifest)
    print('Compiled exact 5F CPU/cache (one job, installed offline image)', flush=True)
    rows, negatives = [], []
    for pattern in fixtures:
        for profile in ['0:0', '2:9']:
            iw, dw = profile.split(':')
            observations = []
            for repeat in range(2):
                name = f'{pattern}-{iw}-{dw}-{repeat}'
                log = out/(name+'.log')
                common = [f'+payload={cpath(out/"payload.hex")}', f'+firmware={cpath(out/"firmware.hex")}',
                          f'+i_wait={iw}', f'+d_wait={dw}', '+max_cycles=3000000', '+ngage-compact-trace']
                command(docker + [cpath(executable), IMAGE, '+program='+cpath(out/(pattern+'.hex')),
                                 '+span_trace='+str(int(pattern=='forward' and profile=='0:0' and repeat==0)), *common], log)
                text = log.read_text()
                windows = [dict((k, int(v)) for k, v in re.findall(r'(\w+)=(-?\d+)', line))
                           for line in text.splitlines() if line.startswith('SPAN_WINDOW ')]
                assert len(windows)==7 and 'RESULT windows=7 ' in text
                assert [w['index'] for w in windows] == list(range(7))
                for w in windows:
                    assert w['instructions']==oracles[pattern]['instructions']==20*PIXELS
                    assert sum(w[k] for k in ['read_stall','write_stall','load_lock','shift_lock','empty','other'])==w['cycles']
                    assert w['last_ram'] <= w['last_store_retire'] <= w['cycles']
                    assert w['mla_busy']==4*PIXELS and w['mla_s2_exposed']==PIXELS
                for w in windows[2:]:
                    assert all(w[k]==0 for k in ['reads','writes','lines','beats']), 'score not fully resident'
                observations.append(windows)
            assert observations[0]==observations[1], 'repeated runs differ'
            scored = observations[0][2:]
            median = statistics.median(w['cycles'] for w in scored)
            rows.append(dict(pattern=pattern, profile=profile, pixels=PIXELS, windows=observations[0],
                             cycles_median=median, cycles_per_pixel=median/PIXELS, repeats_equal=2))
            print(pattern, profile, median, 'cycles', median/PIXELS, 'cycles/pixel PASS', flush=True)
            name = pattern+'-wrong'
            log = out/f'{name}-{iw}-{dw}.log'
            rc = command(docker+[cpath(executable), IMAGE, '+program='+cpath(out/(name+'.hex')), *common], log, True)
            assert rc != 0 and 'guest result check failed' in log.read_text(), 'corrupted output was accepted'
            negatives.append(dict(pattern=pattern, profile=profile, wrong_actual_pixel_rejected=True))
    for name, sha in source['files'].items():
        assert digest((out/'source'/name).read_bytes())==sha, 'frozen source changed'
    save(out/'result.json', dict(status='PASS', manifest=manifest, oracle=oracles, rows=rows, negatives=negatives,
                                meaning='Original loop fixed-work CPU/cache simulation, no FPS inference'))
    print('PASS:', out/'result.json', flush=True)


if __name__ == '__main__':
    main()
