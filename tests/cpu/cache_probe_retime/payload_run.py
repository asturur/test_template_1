#!/usr/bin/env python3
"""Run original SPMark/GLES kernels on a frozen current CPU/cache RTL snapshot."""
import argparse
import hashlib
import importlib.util
import json
import math
import re
import shutil
import statistics
import struct
import subprocess
import sys
import time
from pathlib import Path

from workloads import EXPECTED_IMAGES, ROM_SHA, assembly, cases, image

ROOT = Path(__file__).resolve().parents[3]
IMAGE = 'jotego/simulator:arm64'
MODEL = 'spmark-payload-line16-v1'
RUN_OUTPUT = None


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def save(path, data):
    path.write_text(json.dumps(data, indent=2, sort_keys=True)+'\n')


def command(args, log):
    with log.open('w') as f:
        f.write(json.dumps([str(x) for x in args])+'\n')
        f.flush()
        result = subprocess.run([str(x) for x in args], cwd=ROOT,
                                stdout=f, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f'command failed ({result.returncode}): {log}')


def hexfile(path, raw):
    raw = bytes(raw) + bytes((-len(raw)) % 4)
    path.write_text(''.join(f'{v[0]:08x}\n' for v in struct.iter_unpack('<I', raw)))


def cpath(path):
    return '/work/'+str(path.resolve().relative_to(ROOT))


def write_report(out, result):
    if result['status'] != 'PASS':
        raise ValueError('cannot report a failed run as a baseline')
    report = ['# Original SPMark payload CPU/cache results','',result['meaning'],'',
              '| Workload | I:D waits | Operations | Median cycles | Scored range | Cycles/operation |',
              '| --- | --- | ---: | ---: | --- | ---: |']
    for row in result['rows']:
        values = [w['cycles'] for w in row['windows'][2:]]
        report.append(f'| {row["case"]} | {row["profile"]} | {row["operations"]} | '
                      f'{row["body_cycles_median"]} | {min(values)}–{max(values)} | '
                      f'{row["cycles_per_operation"]:.3f} |')
    report += ['', 'Index: '+json.dumps(result['baseline_index_by_profile']),
               '','Two warm-ups, five checked samples; synthetic scalar/line memory, no physical SDRAM/LCD/OS.',
               '',f'Measured wall time including setup, checks and build: {result["elapsed_seconds"]:.3f}s.']
    (out/'report.md').write_text('\n'.join(report)+'\n')


def support():
    # Reuse the maintained source freezer and checked counter parser, without
    # running its historical matrix or touching any of its output directories.
    directory = ROOT/'tests/cpu/donor_import'
    sys.path.insert(0, str(directory))
    spec = importlib.util.spec_from_file_location('cpu_benchmark_support', directory/'run.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def extract_mmc(path, output):
    raw = path.read_bytes()
    if sha(raw) != '60d7c4aa989b2393cbeb8f2bbd563cbce0bad5b33d8bb9dac28d89660a772919':
        raise ValueError('MMC differs from the qualified SPMark image')
    u16 = lambda b, o: struct.unpack_from('<H', b, o)[0]
    base = struct.unpack_from('<I', raw, 454)[0]
    boot = raw[base*512:(base+1)*512]
    spc, reserved, nf, roots, spf = boot[13], u16(boot,14), boot[16], u16(boot,17), u16(boot,22)
    fs = base+reserved
    fat = raw[fs*512:(fs+spf)*512]
    root = fs+nf*spf
    data = root+(roots*32+511)//512

    def content(cluster):
        chunks, seen = [], set()
        while cluster < 0xff8:
            if cluster < 2 or cluster in seen:
                raise ValueError('invalid FAT12 chain')
            seen.add(cluster)
            start = (data+(cluster-2)*spc)*512
            if start+spc*512 > len(raw)-512:
                raise ValueError('cluster outside card')
            chunks.append(raw[start:start+spc*512])
            v = u16(fat, cluster+cluster//2)
            cluster = ((v >> 4) if cluster & 1 else v) & 0xfff
        return b''.join(chunks)

    def directory(buf):
        lfn = {}
        for i in range(0, len(buf), 32):
            e = buf[i:i+32]
            if not e[0]: break
            if e[0] == 0xe5: lfn = {}; continue
            if e[11] == 15:
                lfn[e[0]&31] = (e[1:11]+e[14:26]+e[28:32]).decode('utf-16le')
                continue
            short = e[:8].decode().rstrip()+('.'+e[8:11].decode().rstrip() if e[8:11].strip() else '')
            name = ''.join(lfn[k] for k in sorted(lfn)).split('\0')[0] if lfn else short
            lfn = {}
            if short in ('.', '..') or e[11] & 8: continue
            cluster = u16(e,26)
            if e[11]&16: directory(content(cluster))
            elif name in EXPECTED_IMAGES:
                value = content(cluster)[:struct.unpack_from('<I',e,28)[0]]
                if sha(value) != EXPECTED_IMAGES[name]: raise ValueError('payload mismatch')
                (output/name).write_bytes(value)
    directory(raw[root*512:root*512+roots*32])


def main():
    global RUN_OUTPUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name', required=True)
    parser.add_argument('--payload-dir', type=Path,
                        default=ROOT/'tests/cpu/spmark_payload/local')
    parser.add_argument('--mmc', type=Path, help='extract qualified modules from this local card image')
    parser.add_argument('--rom', type=Path, default=ROOT/'build/firmware/nem4-factory/core.bin')
    parser.add_argument('--case', action='append')
    parser.add_argument('--profile', action='append', help='synthetic I:D extra waits; default0:0 and2:9')
    parser.add_argument('--repeat', type=int, default=2)
    parser.add_argument('--jobs', type=int, default=4)
    parser.add_argument('--baseline', type=Path)
    parser.add_argument('--reuse-build', type=Path,
                        help='reuse a compiled run only if frozen RTL/harness/image/binary hashes match')
    parser.add_argument('--skip-qualification', action='store_true')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,63}', args.name):
        parser.error('invalid name')
    if args.repeat < 1 or not 1 <= args.jobs <= 8: parser.error('invalid repeat/jobs')
    profiles = args.profile or ['0:0', '2:9']
    if len(set(profiles)) != len(profiles) or any(not re.fullmatch(r'\d+:\d+', x) for x in profiles):
        parser.error('profiles must be unique nonnegative I:D waits')
    selected = [c for c in cases() if not args.case or c['id'] in args.case]
    if not selected or set(args.case or [])-{c['id'] for c in selected}: parser.error('unknown case')
    out = ROOT/'build/sim/spmark-payload'/args.name
    out.mkdir(parents=True, exist_ok=False)
    RUN_OUTPUT = out
    started = time.monotonic()
    save(out/'result.json', dict(status='INCOMPLETE', rows=[]))
    libs = args.payload_dir
    if args.mmc:
        libs = out/'modules'
        libs.mkdir()
        extract_mmc(args.mmc, libs)
    rom = args.rom.read_bytes()
    if sha(rom) != ROM_SHA: raise ValueError('original firmware hash differs')
    firmware = rom[0x300000:0x400000]
    hexfile(out/'firmware.hex', firmware)
    payloads = {name: image(libs/name) for name in EXPECTED_IMAGES}
    # Normal E32 import linking, not a body patch: GLES's signed divide helper
    # calls original EUSER ordinal1514. Both its IAT ordinal and native export
    # table entry are checked against the hash-pinned ROM. No host math stub.
    iat, ordinal, target, exports = 0x199a0, 1514, 0x503a2f6c, 0x503cab7c
    if struct.unpack_from('<I', payloads['libGLES_CM.dll'], iat)[0] != ordinal:
        raise ValueError('unexpected GLES divide import')
    if struct.unpack_from('<I', rom, exports-0x50000000+(ordinal-1)*4)[0] != target:
        raise ValueError('native EUSER export differs')
    struct.pack_into('<I', payloads['libGLES_CM.dll'], iat, target)
    for name, payload in payloads.items(): hexfile(out/(name+'.hex'), payload)
    from oracle import verify
    oracle = {c['id']: verify(c, payloads[c['module']], firmware) for c in selected}
    save(out/'oracle.json', oracle)
    print('PASS: independent original-byte oracle and mathematical outputs', flush=True)
    bench = support()
    source = out/'source'
    frozen = bench.snapshot(source)
    tb = Path(__file__).with_name('tb.v')
    shutil.copyfile(tb, out/'tb.v')
    programs = {}
    for c in selected:
        for bad in [False, True] if not args.skip_qualification else [False]:
            name = c['id']+('-wrong-output' if bad else '')
            asm = out/(name+'.S')
            asm.write_text(assembly(c, corrupt=bad))
            command(['arm-none-eabi-gcc','-c','-mcpu=arm920t','-marm',asm,'-o',out/(name+'.o')],out/(name+'.assemble.log'))
            command(['arm-none-eabi-ld','-T',ROOT/'sim/programs/link.ld',out/(name+'.o'),'-o',out/(name+'.elf')],out/(name+'.link.log'))
            command(['arm-none-eabi-objcopy','-O','binary',out/(name+'.elf'),out/(name+'.bin')],out/(name+'.objcopy.log'))
            raw = (out/(name+'.bin')).read_bytes()
            if len(raw) > 0x40000: raise ValueError('wrapper exceeds modeled ROM')
            hexfile(out/(name+'.hex'),raw)
            symbols = bench.symbols(subprocess.check_output(['arm-none-eabi-nm',out/(name+'.elf')]).decode())
            programs[name] = dict(symbols, sha256=sha(raw))
    image_id = subprocess.check_output(['docker','image','inspect',IMAGE,'--format','{{.Id}}']).decode().strip()
    manifest = dict(format=MODEL, source=frozen, image_id=image_id, harness_sha256=sha(tb.read_bytes()),
                    programs=programs, payload_sha256={k:sha(v) for k,v in payloads.items()},
                    original_images=EXPECTED_IMAGES, original_rom_sha256=ROM_SHA,
                    normal_import_link=dict(iat=hex(iat),ordinal=ordinal,target=hex(target)),
                    profiles=profiles, repeat=args.repeat)
    save(out/'manifest.json', manifest)
    docker = ['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64',
              '-v',str(ROOT)+':/work','-w','/work','--entrypoint']
    rtl = [source/'rtl/ngage_cpu.sv',source/'rtl/ngage_bram.v']
    for directory in ['rtl/arm','rtl/arm920']:
        rtl += sorted(p for p in (source/directory).iterdir() if p.suffix in ('.v','.sv'))
    executable = out/'obj/Vbench'
    if args.reuse_build:
        previous = json.loads((args.reuse_build/'manifest.json').read_text())
        for field in ['format','harness_sha256','image_id']:
            if previous[field] != manifest[field]: raise ValueError('build reuse differs: '+field)
        if previous['source']['source_id'] != frozen['source_id']:
            raise ValueError('build reuse refused: RTL snapshot differs')
        executable = ROOT/previous['executable']
        if sha(executable.read_bytes()) != previous['executable_sha256']:
            raise ValueError('cached executable changed')
        print('Reused verified unchanged CPU/cache executable',flush=True)
    else:
        command(docker+['verilator',IMAGE,'--binary','--timing','--assert','-j',str(args.jobs),
                        '-Wno-fatal','-Wno-lint','-DNGAGE_RUNTIME_TRACE','-DBENCH_HAS_LINE',
                        '-GLINE_ENABLE=1','--top-module','bench','--Mdir',cpath(out/'obj'),
                        '-I'+cpath(source/'rtl/arm')]+[cpath(p) for p in rtl]+[cpath(out/'tb.v')], out/'build.log')
        print('Compiled frozen current CPU/cache RTL',flush=True)
    manifest['executable'] = str(executable.relative_to(ROOT))
    manifest['executable_sha256'] = sha(executable.read_bytes())
    save(out/'manifest.json',manifest)
    rows, qualification = [], []
    for c in selected:
        names = [c['id']] + ([c['id']+'-wrong-output'] if not args.skip_qualification else [])
        for name in names:
            bad = name.endswith('-wrong-output')
            for profile in profiles[:1] if bad else profiles:
                iw, dw = profile.split(':')
                observations = []
                for repeat in range(1 if bad else args.repeat):
                    log = out/f'{name}-{iw}-{dw}-{repeat}.log'
                    args_ = docker+[cpath(executable),IMAGE,
                          '+program='+cpath(out/(name+'.hex')),
                          '+payload='+cpath(out/(c['module']+'.hex')),
                          '+firmware='+cpath(out/'firmware.hex'),
                          f'+begin_pc={programs[name]["body_begin"]:x}',f'+end_pc={programs[name]["body_end"]:x}',
                          f'+i_wait={iw}',f'+d_wait={dw}','+max_cycles=30000000','+ngage-compact-trace']
                    try:
                        command(args_,log)
                    except RuntimeError:
                        if bad and 'guest result check failed' in log.read_text():
                            qualification.append(dict(case=c['id'],status='PASS',wrong_output_rejected=True))
                            continue
                        raise
                    if bad: raise ValueError('wrong mathematical output was accepted')
                    observation = bench.parse_log(log.read_text(), c)
                    payload_windows = [dict((k,int(v)) for k,v in re.findall(r'(\w+)=(\d+)',l))
                                       for l in log.read_text().splitlines() if l.startswith('PAYLOAD_WINDOW ')]
                    if len(payload_windows) != c['warmups']+c['samples'] or any(w['payload_retire_proxy'] <= 0 for w in payload_windows):
                        raise ValueError('missing actual payload execution')
                    expected = oracle[c['id']]
                    if any(w['payload_retire_proxy'] != expected['payload_instructions'] or
                           w['helper_retire_proxy'] != expected['helper_instructions']
                           for w in payload_windows):
                        raise ValueError('RTL payload/helper execution differs from independent oracle')
                    observation['payload_windows'] = payload_windows
                    observations.append(observation)
                if not bad:
                    if any(x != observations[0] for x in observations[1:]):
                        raise ValueError('identical repeated runs differ')
                    row = dict(case=c['id'],profile=profile,operations=c['operations'],unit=c['unit'],
                               program_sha256=programs[name]['sha256'],oracle=oracle[c['id']],
                               deterministic_repeats=args.repeat,**observations[0])
                    rows.append(row)
                    print(c['id'],profile,'PASS',row['body_cycles_median'],'cycles',flush=True)
                    save(out/'result.json', dict(status='INCOMPLETE',manifest=manifest,rows=rows))
    # Matching source/input hashes protect against accidental mixed snapshots.
    for name, expected in frozen['files'].items():
        if sha((source/name).read_bytes()) != expected: raise ValueError('frozen RTL changed')
    result = dict(status='PASS', manifest=manifest,rows=rows,qualification=qualification,
                  elapsed_seconds=round(time.monotonic()-started,3),
                  baseline_index_by_profile={p:100.0 for p in profiles},
                  meaning='Fixed original-payload CPU/cache index; not official SPMark score or board FPS')
    if args.baseline:
        old = json.loads(args.baseline.read_text())
        if old['status'] != 'PASS': raise ValueError('baseline did not pass')
        for field in ['format','image_id','harness_sha256','payload_sha256','original_rom_sha256']:
            if old['manifest'][field] != manifest[field]: raise ValueError('baseline differs: '+field)
        base = {(r['case'],r['profile']):r for r in old['rows']}
        if set(base) != {(r['case'],r['profile']) for r in rows}: raise ValueError('baseline group membership differs')
        for row in rows:
            b = base[row['case'],row['profile']]
            if b['program_sha256'] != row['program_sha256']: raise ValueError('guest code differs')
            row['throughput_ratio'] = b['body_cycles_median']/row['body_cycles_median']
        result['baseline_index_by_profile'] = {p:100*math.exp(statistics.mean(math.log(r['throughput_ratio']) for r in rows if r['profile']==p)) for p in profiles}
        result['baseline'] = str(args.baseline)
    save(out/'result.json',result)
    write_report(out, result)
    print('PASS:',out/'result.json',flush=True)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError,ValueError,RuntimeError,subprocess.CalledProcessError) as exc:
        if RUN_OUTPUT is not None:
            result = json.loads((RUN_OUTPUT/'result.json').read_text())
            result.update(status='FAIL', error=str(exc))
            save(RUN_OUTPUT/'result.json', result)
        print('FAIL:',exc,file=sys.stderr)
        sys.exit(1)
