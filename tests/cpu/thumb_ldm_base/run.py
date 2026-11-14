#!/usr/bin/env python3
"""Run Thumb LDM regressions in isolated outputs using the production CPU bench."""
import argparse
import os
from pathlib import Path
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, default=Path('build/sim/unit-thumb-ldm-base'))
    parser.add_argument('--program', default='thumb_ldm_base_in_list')
    parser.add_argument('--skip-decode', action='store_true')
    args = parser.parse_args()
    out = args.out
    if out.is_absolute() or '..' in out.parts or not out.parts or out.parts[0] != 'build':
        parser.error('--out must be a relative directory under build/')
    os.chdir(ROOT)
    out.mkdir(parents=True, exist_ok=True)
    if not args.skip_decode:
        command = ['docker', 'run', '--rm', '--network', 'none', '--platform', 'linux/arm64',
                   '-v', f'{ROOT}:/work', '-w', '/work', '--entrypoint', 'verilator',
                   'jotego/simulator:arm64', '--binary', '--timing', '--assert',
                   '-Wno-fatal', '-Wno-lint', '-Irtl/arm', '--top-module', 'test',
                   '--Mdir', str(out/'decode'), 'rtl/arm/zap_mode16_decoder.sv',
                   'tests/cpu/thumb_ldm_base/decode.v']
        with (out/'decode-build.log').open('w') as log:
            subprocess.run(command, check=True, stdout=log, stderr=subprocess.STDOUT)
        subprocess.run(command[:command.index('--entrypoint')+1]
                       + [f'/work/{out}/decode/Vtest', 'jotego/simulator:arm64'], check=True)
    # Generate a path-only copy: the original shared unit-core outputs and any
    # other thread's simulation objects/checkpoints remain untouched.
    test = (ROOT/'tests/cpu/core/test.sv').read_text()
    (out/'test.sv').write_text(test.replace('build/sim/unit-core', str(out)))
    script = (ROOT/'tests/cpu/core/sim.sh').read_text()
    start = script.index('root=')
    end = script.index('\n', start)
    script = script[:start] + 'root=' + shlex.quote(str(ROOT)) + script[end:]
    script = script.replace('build/sim/unit-core', str(out))
    script = script.replace('tests/cpu/core/test.sv', str(out/'test.sv'))
    runner = out/'run.sh'
    runner.write_text(script)
    subprocess.run(['sh', str(runner)], check=True,
                   env=dict(os.environ, CPU_PROGRAM=args.program))


if __name__ == '__main__':
    main()
