#!/usr/bin/env python3
"""Reproduce the native privileged single-register block-transfer fault.

Runs actual CPU/MMU/cache RTL in an isolated generated core fixture. Explicit
LDRT/STRT controls must still abort on the same AP1/domain1 small page.
Optional candidate directory replaces named RTL only; no operand-reference mode.
"""
import argparse
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--name', required=True)
parser.add_argument('--candidate', type=Path)
args = parser.parse_args()
out = Path('build/sim') / args.name
if out.is_absolute() or '..' in out.parts:
    parser.error('name must stay under build/sim')
(ROOT / out).mkdir(parents=True, exist_ok=False)
script = (ROOT / 'tests/cpu/core/sim.sh').read_text()
script = script.replace('root=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)', 'root=' + str(ROOT))
script = script.replace('build/sim/unit-core', str(out))
script = script.replace('testbench=tests/cpu/core/test.sv', 'testbench=' + str(out / 'test.sv'))
script = script.replace('extra_define="-DNGAGE_OPERAND_REFERENCE"', 'extra_define=""')
script = script.replace('--binary --timing', '--binary -j 4 --timing')
script = script.replace('docker run --rm --network', 'docker run --rm --pull=never --network')
(ROOT / out / 'test.sv').write_text((ROOT / 'tests/cpu/core/test.sv').read_text().replace('build/sim/unit-core', str(out)))
run = ROOT / out / 'run.sh'
run.write_text(script)
for label, define in [('load', ''), ('store', '-DBLOCK_SINGLE_STORE'),
                      ('ldrt', '-DEXPLICIT_USER_LOAD'), ('strt', '-DEXPLICIT_USER_STORE')]:
    env = os.environ.copy()
    env.update(CPU_PROGRAM='block_transfer_privileged', CPU_ASM_DEFINES=define,
               CPU_DELAYS='0 3', CPU_MAX_CYCLES='500000')
    if args.candidate:
        env['CPU_REFERENCE_DIR'] = str(args.candidate.resolve().relative_to(ROOT))
    else:
        env.pop('CPU_REFERENCE_DIR', None)
    log = ROOT / out / (label + '.log')
    with log.open('w') as stream:
        result = subprocess.run(['sh', str(run)], cwd=ROOT, env=env,
                                stdout=stream, stderr=subprocess.STDOUT)
    text = log.read_text()
    if result.returncode or text.count('PASS: CPU test') != 2:
        raise RuntimeError(label + ' failed: ' + str(log))
    print(label + ': ' + '\n'.join(line for line in text.splitlines() if line.startswith('PASS:')), flush=True)
print('PASS privileged single IA load/store and explicit user-access controls; delays0/3')
