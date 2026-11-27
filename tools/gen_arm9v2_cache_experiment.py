#!/usr/bin/env python3
"""Build a phone CPU geometry from an overlay on the pinned donor source."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from gen_arm9v2_phone import ROOT, VENDOR, edit, expose, expose_block_writeback, fold_section_index

GEOMETRIES = (2, 4, 8, 16, 32, 64)
PATCH = Path(__file__).with_name('arm9v2_cache_associativity.patch')
DIRTY_PATCH = Path(__file__).with_name('arm9v2_cache_half_dirty.patch')


def generate(iways, dways, output, dirty='line', stream_writeback=False):
    build = ROOT / 'build'
    build.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='arm9v2-geometry-', dir=build) as temporary:
        source = Path(temporary) / 'upstream'
        shutil.copytree(VENDOR / 'upstream', source)
        patches = (PATCH,) if dirty == 'line' else (PATCH, DIRTY_PATCH)
        for overlay in patches:
            with overlay.open('rb') as patch:
                subprocess.run(['patch', '-s', '-p1'], cwd=source, stdin=patch, check=True)
        stock = Path(temporary) / 'arm925t_exp.v'
        subprocess.run(['bash', source / 'tools/gen_cpu.sh', stock], check=True,
                       env=dict(os.environ, TMPDIR=temporary))
        phone = expose(stock.read_text())
    phone = edit(phone, 'ICACHE_WAYS = 2;', f'ICACHE_WAYS = {iways};')
    phone = edit(phone, 'DCACHE_WAYS = 2;', f'DCACHE_WAYS = {dways};')
    ctype = (0x0514A14A & ~0x38038) | ((iways.bit_length()-1) << 3) | ((dways.bit_length()-1) << 15)
    phone = edit(phone, ".CP15_CTYPE(32'h0514a14a)", f".CP15_CTYPE(32'h{ctype:08x})")
    if dirty == 'half':
        phone = edit(phone, "localparam [0:0] HALF_WRITEBACK = 1'b0;",
                     "localparam [0:0] HALF_WRITEBACK = 1'b1;")
    if stream_writeback:
        phone = expose_block_writeback(fold_section_index(phone))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(phone)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--iways', type=int, choices=GEOMETRIES, required=True)
    parser.add_argument('--dways', type=int, choices=GEOMETRIES, required=True)
    parser.add_argument('--dirty', choices=('line', 'packed', 'half'), default='line')
    parser.add_argument('--stream-writeback', action='store_true',
                        help='apply the production section index and 16-byte writeback interface')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    generate(args.iways, args.dways, args.output, args.dirty, args.stream_writeback)


if __name__ == '__main__':
    main()
