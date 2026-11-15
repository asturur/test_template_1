#!/usr/bin/env python3
"""ARM920T guest profile and preserved ARMv4T CPU regressions, isolated outputs."""
import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[3]
EXTENSIONS = {
    'clz': 0xe16f0f15, 'blx_register': 0xe12fff35, 'bkpt': 0xe1200070,
    'qadd': 0xe1050056, 'qsub': 0xe1250056, 'qdadd': 0xe1450056,
    'qdsub': 0xe1650056, 'smul': 0xe1600685, 'smla': 0xe10006c5,
    'smlaw': 0xe12006a5, 'smulw': 0xe1200685, 'smlal_half': 0xe14106e5,
    'ldrd': 0xe1c400d0, 'strd': 0xe1c400f0, 'cdp': 0xee000000,
    'ldc': 0xec940500, 'undefined_transfer': 0xe6000010,
    'absent_mrc': 0xee100510, 'absent_mcr': 0xee000510,
}
NV_POLICY = [0xfa000000, 0xf5d4f000, 0xfe000f10, 0xfe100f10,
             0xfe000000, 0xfd940500, 0xf0000000]
USER_CP15 = [0xee100f10, 0xee070f9a]
REGRESSIONS = [
    'smoke', 'cpu_timing', 'operand_timing', 'thumb_return_dependency',
    'thumb_ldm_base_in_list', 'swp_irq_core', 'swp_basic', 'swp_cached_irq',
    'swp_fiq', 'fiq_flash_return', 'data_privilege_owner', 'mmu_fetch',
    'cache_load_widths', 'cache_irq_refill', 'cache_irq_writeback',
]


def condition(cc, flags):
    n, z, c, v = [(flags >> bit) & 1 for bit in (3, 2, 1, 0)]
    return [z, not z, c, not c, n, not n, v, not v,
            c and not z, not c or z, n == v, n != v,
            not z and n == v, z or n != v, True][cc]


def matrix(opcodes):
    return [(word & 0x0fffffff | cc << 28, flags << 28,
             int(condition(cc, flags)))
            for word in opcodes for cc in range(15) for flags in range(16)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--profile-only', action='store_true')
    parser.add_argument('--reference-dir', type=Path)
    args = parser.parse_args()
    os.chdir(ROOT)
    out = args.out
    if out.is_absolute() or '..' in out.parts or out.parts[:1] != ('build',):
        parser.error('--out must be an isolated relative directory under build/')
    out.mkdir(parents=True, exist_ok=False)
    arm = matrix(EXTENSIONS.values()) + [(word, 0, 1) for word in NV_POLICY]
    user = matrix(USER_CP15)
    table = ''.join(f'.word 0x{word:08x},0x{flags:08x},{trap}\n'
                    for word, flags, trap in arm)
    table += 'user_cases:\n' + ''.join(
        f'.word 0x{word:08x},0x{flags:08x},{trap}\n' for word, flags, trap in user)
    (out/'cases.inc').write_text(table)
    common = (ROOT/'sim/programs/common.inc').read_text().replace(
        'b undefined_handler', 'b profile_undefined_handler')
    (out/'common.inc').write_text(common)
    program = (Path(__file__).parent/'program.S').read_text().replace(
        'sim/programs/common.inc', str(out/'common.inc')).replace(
        '@CASES@', str(out/'cases.inc'))
    program = f'.equ ARM_CASE_COUNT,{len(arm)}\n.equ USER_CASE_COUNT,{len(user)}\n' + program
    (out/'program.S').write_text(program)
    (out/'test.sv').write_text((ROOT/'tests/cpu/core/test.sv').read_text().replace(
        'build/sim/unit-core', str(out)))
    script = (ROOT/'tests/cpu/core/sim.sh').read_text()
    start = script.index('root=')
    script = script[:start] + 'root=' + shlex.quote(str(ROOT)) + script[script.index('\n', start):]
    script = script.replace('build/sim/unit-core', str(out)).replace(
        'tests/cpu/core/test.sv', str(out/'test.sv')).replace('--binary --timing', '--binary -j 4 --timing')
    env = dict(os.environ, CPU_MAX_CYCLES='10000000')
    if args.reference_dir:
        env['CPU_REFERENCE_DIR'] = str(args.reference_dir)
    programs = ['../../' + str(out/'program')]
    if not args.profile_only:
        programs += REGRESSIONS
    summary = {'status': 'INCOMPLETE', 'arm_cases': len(arm), 'user_cp15_cases': len(user),
               'thumb_undefined_cases': 4, 'extensions': EXTENSIONS, 'programs': {}}
    try:
        for index, name in enumerate(programs):
            selected = script
            if index:
                # The same frozen testbench executable reads the next program.hex.
                begin = selected.index('docker run --rm --network none')
                end = selected.index('\nextra=', begin)
                selected = selected[:begin] + selected[end:]
            (out/'run.sh').write_text(selected)
            label = 'armv4t_profile' if not index else name
            with (out/f'{label}.log').open('w') as log:
                subprocess.run(['sh', str(out/'run.sh')], check=True,
                               env=dict(env, CPU_PROGRAM=name), stdout=log,
                               stderr=subprocess.STDOUT)
            summary['programs'][label] = {}
            for delay in env.get('CPU_DELAYS', '0 3').split():
                run = (out/f'run-{delay}.log')
                content = run.read_text()
                if 'PASS:' not in content:
                    raise RuntimeError(f'{label}/{delay}: missing completion')
                metrics = [line for line in content.splitlines() if line.startswith(
                    ('PASS:', 'TIMING:', 'STALL:', 'COUNTERS:', 'METRICS:', 'PHASES:', 'INIT_EDGES:'))]
                summary['programs'][label][delay] = metrics
                run.rename(out/f'{label}-{delay}.log')
            print(f'PASS: {label}', flush=True)
        summary['status'] = 'PASS'
    except Exception:
        summary['status'] = 'FAIL'
        raise
    finally:
        (out/'result.json').write_text(json.dumps(summary, indent=2) + '\n')


if __name__ == '__main__':
    main()
