"""Replay an original EFile FAT write to a private, reopened host file."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

from verify_card import CARD_SHA, verify

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
ROM_SHA = 'be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524'


def sha(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def edit(text, before, after):
    assert text.count(before) == 1, before
    return text.replace(before, after)


def prepare(ref, work):
    for name in ('sw', 'tools'):
        shutil.copytree(ref/name, work/name, ignore=shutil.ignore_patterns('__pycache__'))
    shutil.copyfile(HERE/'guest.c', work/'sw/kernel/launch.c')
    header = work/'sw/include/ngvm_hw.h'
    header.write_text(edit(header.read_text(), '#define NGVM_IMAGE_MAX    0x04000000u',
                           '#define NGVM_IMAGE_MAX    0x08000000u'))
    drive = work/'sw/kernel/drive.c'
    s = edit(drive.read_text(), '    if (!t) r = KErrBadHandle;',
             '    if (l->unit == 2 && write && IO(0x0e0) != 1) r = KErrAccessDenied;\n'
             '    else if (!t) r = KErrBadHandle;')
    s = edit(s, '        if (q->write) { from_des(q->t, q->buf, a, n, q->off); slot_pin[s] = 1; }',
        '''        if (q->write) {
            q->r = from_des(q->t, q->buf, a, n, q->off);
            if (q->r != KErrNone) return 1;
            IO(0x0e4) = q->pos;
            IO(0x0e8) = a;
            IO(0x0ec) = n;
            slot_pin[s] = 1;
        }''')
    drive.write_text(s)
    python = work/'tools/ngvm/ngvm.py'
    s = edit(python.read_text(), "            self.image = open(args.drive, 'rb').read()",
             '''            self.card = open(args.drive, 'r+b' if args.card_mode == 1 else 'rb', buffering=0)
            raw = self.card.read()
            self.partition_start = int.from_bytes(raw[454:458], 'little') * 512
            partition_size = int.from_bytes(raw[458:462], 'little') * 512
            assert self.partition_start + partition_size <= len(raw) - 512
            self.image = bytearray(raw[self.partition_start:self.partition_start + partition_size])
            self.write_pos = self.write_pointer = None
            self.writes = []''')
    s = edit(s, 'uc.mem_write(NGVM_DRIVE_BASE, self.image[:NGVM_DRIVE_MAX])',
             'uc.mem_write(NGVM_DRIVE_BASE, bytes(self.image[:NGVM_DRIVE_MAX]))')
    s = edit(s, 'self.uc.mem_write(NGVM_DRIVE_BASE + dst, self.image[src:src + n])',
             'self.uc.mem_write(NGVM_DRIVE_BASE + dst, bytes(self.image[src:src + n]))')
    s = edit(s, "        if off == IO_DRIVE_SIZE:", "        if off == 0x0e0:\n            return self.a.card_mode\n        if off == IO_DRIVE_SIZE:")
    s = edit(s, "        if off == IO_DBG_PUTC:", '''        if off == 0x0e4:
            self.write_pos = value
        elif off == 0x0e8:
            self.write_pointer = value
        elif off == 0x0ec:
            assert self.a.card_mode == 1
            pos = self.write_pos
            assert 0 < value <= 65536 and 0 <= pos <= len(self.image) - value
            assert NGVM_DRIVE_BASE <= self.write_pointer <= NGVM_DRIVE_BASE + NGVM_DRIVE_MAX - value
            block = bytes(uc.mem_read(self.write_pointer, value))
            disk_offset = self.partition_start + pos
            assert os.pwrite(self.card.fileno(), block, disk_offset) == value
            self.image[pos:pos + value] = block
            self.writes.append((disk_offset, block.hex()))
            print('ROUNDTRIP drive-write', disk_offset, value, flush=True)
        elif off == IO_DBG_PUTC:''')
    s = edit(s, "    ap.add_argument('--drive')", """    ap.add_argument('--drive', required=True)
    ap.add_argument('--card-mode', type=int, required=True, choices=(0, 1, 2))
    ap.add_argument('--write-journal', required=True)""")
    s = edit(s, '    sys.exit(m.run())', '''    code = m.run()
    if a.card_mode == 1:
        os.fsync(m.card.fileno())
    m.card.close()
    import json
    with open(a.write_journal, 'w') as f:
        json.dump(m.writes, f)
    sys.exit(code)''')
    python.write_text(s)
    with (work/'build.log').open('w') as log:
        subprocess.run(['make', '-C', work/'sw/kernel'], stdout=log,
                       stderr=subprocess.STDOUT, check=True, timeout=150)


def run_guest(work, rom, card, name, mode):
    journal = work.parent/(name+'.json')
    log = work.parent/(name+'.log')
    with log.open('w') as f:
        r = subprocess.run([sys.executable, '-u', work/'tools/ngvm/ngvm.py',
            '--rom', rom, '--drive', card, '--seconds', '12', '--mips', '100',
            '--card-mode', str(mode), '--write-journal', journal],
            stdout=f, stderr=subprocess.STDOUT, timeout=120)
    lines = [line for line in log.read_text().splitlines() if line.startswith('ROUNDTRIP ')]
    print(name, lines, flush=True)
    assert r.returncode == 0 and f'ROUNDTRIP done 0 mode {mode}' in lines, log
    return json.loads(journal.read_text())


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('name')
    p.add_argument('--image', type=Path, default=ROOT/'build/mmc/write-test-128mb.mmc')
    p.add_argument('--reference', type=Path, default=ROOT/'build/tool-cache/ngvm4')
    p.add_argument('--rom', type=Path, default=ROOT/'build/firmware/nem4-factory/core.bin')
    args = p.parse_args()
    assert Path(args.name).name == args.name and args.name not in ('.', '..')
    image = args.image.resolve()
    rom = args.rom.resolve()
    assert image.stat().st_size == 134185472 and sha(rom) == ROM_SHA
    out = ROOT/'build/sim'/args.name
    out.mkdir()
    card = out/'guest.mmc'
    before = sha(image)
    assert before == CARD_SHA
    shutil.copyfile(image, card)
    prepare(args.reference.resolve(), out/'reference')
    records = run_guest(out/'reference', rom, card, 'write', 1)
    assert records
    saved = sha(card)
    assert saved != before and not run_guest(out/'reference', rom, card, 'reopen', 0)
    assert not run_guest(out/'reference', rom, card, 'read_only', 2)
    assert sha(card) == saved and sha(image) == before
    report = verify(image, card)
    original = image.read_bytes()
    replay = bytearray(original)
    for pos, data in records:
        b = bytes.fromhex(data)
        replay[pos:pos + len(b)] = b
    persisted = card.read_bytes()
    assert persisted == replay and persisted[-512:] == original[-512:]
    report.update(writes=len(records), written_bytes=sum(len(d)//2 for _, d in records),
                  rom_sha256=ROM_SHA)
    (out/'receipt.json').write_text(json.dumps(report, indent=2)+'\n')
    print('PASS original FAT file, independent bytes, all other files, FAT mirrors and footer')


if __name__ == '__main__':
    main()
