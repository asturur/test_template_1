"""Resolve the relative SPMark names using original EFile on a private NGVM image."""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys

from run import HERE, change

APP_SHA = 'f4d3819d0d7c21f6f669835d03cf9fd8c8b50aa3e0bac6975c4cbaccb09b3a4e'
ROM_SHA = 'afc1cc8b693f2b68d23ca203aa4d4eb4266baad4ab718f013a33b915d39574ef'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--app', type=Path, required=True)
    p.add_argument('--rom', type=Path, required=True)
    p.add_argument('--reference', type=Path, required=True)
    p.add_argument('--cdrive', type=Path, required=True)
    p.add_argument('--name', required=True)
    args = p.parse_args()
    if not re.fullmatch(r'[\w.-]+', args.name):
        p.error('invalid run name')
    app = args.app.read_bytes()
    cdrive = args.cdrive.read_bytes()
    assert sha(app) == APP_SHA and sha(args.rom.read_bytes()) == ROM_SHA
    assert len(cdrive) == 4194304 and bytes.fromhex('603b3b50') in cdrive
    out = (Path('build/sim/disk-access') / args.name).resolve()
    out.mkdir(parents=True)
    for sub in ('sw', 'tools'):
        shutil.copytree(args.reference / sub, out / sub, ignore=shutil.ignore_patterns('__pycache__'))
    kernel = out / 'sw/kernel'
    shutil.copyfile(HERE/'guest.c', kernel/'launch.c')
    length, = struct.unpack_from('<I', app, 0xf6c4)
    assert length == 446 and app[0xf6c8:0xf6cd] == b'Lorem'
    payload = app[0xf6c8:0xf6c8+length]
    (kernel/'disk_payload.h').write_text('static const unsigned char payload[] = {' +
                                        ', '.join(f'0x{b:02x}' for b in payload) + '};\n')
    drives = kernel/'drive.c'
    s = change(drives.read_text(), 'static s32 rw(int write,', 'extern int disk_probe_phase;\nstatic s32 rw(int write,')
    s = change(s, '    u32 size = media[l->unit].size;\n    if (!t)', '''    u32 size = media[l->unit].size;
    if (disk_probe_phase)
        kprintf("DISK_IO phase=%d unit=%d op=%d bytes=%d\\n", disk_probe_phase, l->unit, write, len);
    if (!t)''')
    s = change(s, '    s32 r = KErrNone;\n    if (!media[l->unit].max)', '''    s32 r = KErrNone;
    if (disk_probe_phase)
        kprintf("DISK_IO phase=%d unit=%d op=2 bytes=%d\\n", disk_probe_phase, l->unit, len);
    if (!media[l->unit].max)''')
    drives.write_text(s)
    with (out/'build.log').open('w') as log:
        subprocess.run(['make', '-C', str(kernel)], stdout=log, stderr=subprocess.STDOUT, check=True)
    private = out/'private.vhd'
    private.write_bytes(cdrive)
    with (out/'run.log').open('w') as log:
        subprocess.run([sys.executable, '-u', str(out/'tools/ngvm/ngvm.py'), '--rom', str(args.rom.resolve()),
                        '--save', str(private), '--seconds', '4', '--mips', '100'],
                       stdout=log, stderr=subprocess.STDOUT, check=True, timeout=120)
    raw = (out/'run.log').read_text()
    assert 'PASS DISK_GUEST absolute=C payload=446 files=100' in raw and 'DISK_GUEST_FAIL' not in raw
    assert sha(args.cdrive.read_bytes()) == sha(cdrive)
    rows = [dict(round=int(r), phase=int(p), virtual_us=int(t))
            for r,p,t in re.findall(r'DISK_GUEST round=(\d+) phase=(\d+) elapsed_us=(\d+)', raw)]
    assert len(rows) == 16
    io = defaultdict(lambda: [0, 0])
    for ph, unit, op, size in re.findall(r'DISK_IO phase=(\d+) unit=(\d+) op=(\d+) bytes=(\d+)', raw):
        cell = io[(int(ph), int(unit), int(op))]
        cell[0] += 1
        cell[1] += int(size)
    assert io and all(unit == 0 for _, unit, _ in io)
    result = dict(status='PASS', original_app_sha256=APP_SHA, original_rom_sha256=ROM_SHA,
                  image_input_sha256=sha(cdrive), image_output_sha256=sha(private.read_bytes()),
                  relative_drive='C:', rounds=rows,
                  media=[dict(phase=p, unit=u, op=o, count=n, bytes=b) for (p,u,o),(n,b) in sorted(io.items())])
    (out/'result.json').write_text(json.dumps(result, indent=2)+'\n')
    print(f'PASS {out}')


if __name__ == '__main__':
    main()
