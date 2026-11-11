#!/usr/bin/env python3
"""Extract private original NEM-4 instructions without substitutions."""
import argparse
import hashlib
import json
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('rom', type=Path)
p.add_argument('output', type=Path)
a = p.parse_args()
b = a.rom.read_bytes()
h = hashlib.sha256(b).hexdigest()
if h != '26ca1dd937e299fd4ec3ad65a25d395743ae2149311c3d753cbeb5437673dbc5':
    raise ValueError('Unexpected NEM-4 ROM')
for name, data in [('program', (a.output/'program.bin').read_bytes().ljust(8192,b'\0')),
                   ('app', b[0x320000:0x420000])]:
    (a.output/(name+'.hex')).write_text(''.join(
        f'{int.from_bytes(data[i:i+4], "little"):08x}\n' for i in range(0,len(data),4)))
(a.output/'inputs.json').write_text(json.dumps({
    'rom_sha256': h, 'original_instruction_range': ['50320000','50420000'],
    'original_routines': ['5041a3cc GPIO dispatcher', '5041aa0c scan', '5041ac84 ACK'],
    'instruction_substitutions': [],
    'fixture_only': ['MMU-off original 581xxxxx mapping to board 0c1xxxxx',
                     'bounded program/ROM/zeroed object and stack RAM',
                     'E0000000 public-key input mailbox'],
}, indent=2)+'\n')
