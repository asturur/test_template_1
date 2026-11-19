"""Recheck the established D2 data/alias/reset contract on the two policies."""
import argparse
from pathlib import Path
import re
import subprocess

from run import change, original, update_on_hit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[\w.-]+', args.name):
        parser.error('invalid run name')
    out = Path('build/sim/disk-access') / args.name
    out.mkdir(parents=True)
    run = original('tests/phone/ddr_flash_cache/run.sh')
    files = re.search(r"sources='([^']+)'", run)[1].split()
    files.append('tests/phone/ddr_flash_cache/tb.sv')
    for policy in ('scalar', 'update'):
        leg = out / policy
        leg.mkdir()
        paths = []
        for path in files:
            source = original(path)
            if policy == 'update':
                if path.endswith('/ngage_ddr_flash_cache.v'):
                    source = update_on_hit(source)
                if path.endswith('/tb.sv'):
                    source = change(source, 'read_word(C+64+half*4,m == 0);', 'read_word(C+64+half*4,1);')
            target = leg / Path(path).name
            target.write_text(source)
            paths.append(str(target))
        with (leg/'build.log').open('w') as log:
            subprocess.run(['iverilog', '-g2012', '-s', 'tb', '-Ptb.CACHE_BYTES=32768',
                            '-Ptb.STREAM_TRANSPORT=1', '-o', str(leg/'Vtb'), *paths],
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        with (leg/'run.log').open('w') as log:
            subprocess.run(['vvp', str(leg/'Vtb')], stdout=log, stderr=subprocess.STDOUT, check=True)
        assert 'PASS D2 flash cache' in (leg/'run.log').read_text()
    print(f'PASS {out}')


if __name__ == '__main__':
    main()
