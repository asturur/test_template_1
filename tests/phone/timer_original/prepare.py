#!/usr/bin/env python3
"""Extract exact NEM-4 instructions; reject other firmware, patch nothing."""
import hashlib
import json
import sys
from pathlib import Path
rom_path, out = map(Path, sys.argv[1:])
rom = rom_path.read_bytes()
digest = hashlib.sha256(rom).hexdigest()
if digest != '26ca1dd937e299fd4ec3ad65a25d395743ae2149311c3d753cbeb5437673dbc5':
    raise ValueError('Unexpected NEM-4 fixture ROM')
def words(name, data):
    assert len(data) % 4 == 0
    (out/name).write_text(''.join(f'{int.from_bytes(data[i:i+4], "little"):08x}\n'
                                for i in range(0,len(data),4)))
words('program.hex',(out/'program.bin').read_bytes().ljust(8192,b'\0'))
words('app.hex',rom[0x320000:0x3d0000])
words('boot.hex',rom[0x3000:0x3300])
(out/'inputs.json').write_text(json.dumps({
    'rom_sha256': digest,
    'boot_slice_sha256': hashlib.sha256(rom[0x3000:0x3300]).hexdigest(),
    'kernel_slice_sha256': hashlib.sha256(rom[0x320000:0x3d0000]).hexdigest(),
    'original_instruction_ranges': ['00003000..000032ff','50320000..503cffff'],
    'instruction_substitutions': [],
    'fixture_only': ['MMIO virtual5812xxxx->physical0c12xxxx mapping',
                     'bounded kernel scratch RAM; tick count10, registered test callback',
                     'timer1 DFC-already-queued state for ISR ACK branch',
                     'highresolution scheduler registration excluded; exact init helper calls',
                     'manual ISR invocation; CPU IRQ/FIQ entry is a separate board test'],
},indent=2)+'\n')
