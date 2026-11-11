#!/usr/bin/env python3
"""Write the focused fixture's compact evidence from successful local runs."""
import hashlib
import json
import os
import re
import sys
from pathlib import Path

OUT = Path(os.environ.get('PHONE_TEST_OUT', 'scratch/ngage2-integration/lcd-handover/isr'))
SOURCES = sorted(set(
    list(Path('tests/phone/dma_isr').glob('*'))
    + list(Path('rtl/arm').glob('*.sv'))
    + list(Path('rtl/arm').glob('*.svh'))
    + list(Path('rtl/arm920').glob('*.sv'))
    + [Path(name) for name in ('sim/programs/link.ld', 'rtl/ngage_cpu.sv', 'rtl/ngage_bram.v',
                              'rtl/ngage_dma_engine.v', 'rtl/ngage_dma_channels.v',
                              'rtl/ngage_dma_route.v')]
))


def main():
    hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in SOURCES if path.is_file()}
    snapshot = OUT / 'source-inputs.json'
    if '--snapshot' in sys.argv:
        snapshot.write_text(json.dumps(hashes, indent=2) + '\n')
        return
    if hashes != json.loads(snapshot.read_text()):
        raise ValueError('Fixture sources changed during build/run; rerun required')
    results = []
    for wait in (0, 3):
        path = OUT / f'run-{wait}.log'
        lines = [line for line in path.read_text().splitlines() if line.startswith('PASS ')]
        if len(lines) != 1:
            raise ValueError(f'Expected one successful result in {path}')
        fields = dict(re.findall(r'(\w+)=([^ ]+)', lines[0]))
        if fields['wait'] != str(wait) or fields['substitutions'] != '0':
            raise ValueError('Unexpected fixture result')
        results.append({'wait_cycles': wait, 'cycles': int(fields['cycles']),
                        'result': lines[0], 'log_sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    manifest = {
        'scope': 'Original ISR called directly on ZAP; no full kernel IRQ dispatch claim',
        'inputs': json.loads((OUT / 'inputs.json').read_text()),
        'simulator_image': (OUT / 'image-id.txt').read_text().strip(),
        'results': results,
        'source_sha256': hashes,
        'executable_sha256': hashlib.sha256((OUT / 'obj/Vtb').read_bytes()).hexdigest(),
        'checks': ['remaining-zero exactly one callback',
                   'positive remaining original next chunk then final callback',
                   'channel ACK before restart and callback',
                   'original IRQ-disable wrapper and mask write',
                   'all 4096 SDRAM bytes and source/guard preservation',
                   'no original instruction substitutions'],
    }
    (OUT / 'results.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    main()
