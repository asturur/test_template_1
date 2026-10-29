#!/usr/bin/env python3
"""Offline EKA1 thread-state inspector over a simulation board checkpoint.

Parses build/sim/checkpoints/<name>.host, locates the 16 MB SDRAM image
(board ram_, PA 0x0a000000), maps the kernel home section (VA 0x80000000+x
<-> SDRAM offset x; verified against anchors observed in instruction traces),
and scans for kernel objects: words whose value lies in the ekern vtable
range, grouped by vtable, with nearby pointers to ASCII names dereferenced.

Usage: inspect_checkpoint.py <checkpoint.host> [--vtable 0xADDR] [--dump 0xVA]
This is a discovery tool: output is candidates + context, not gospel.
(made with Claude, 2026-10-29)
"""
import struct, sys
from pathlib import Path

SDRAM_SIZE = 0x1000000
SDRAM_PA = 0x0a000000
KHOME_VA = 0x80000000
ROM_VA = 0x50000000
EKERN_LO, EKERN_HI = 0x50320f9c, 0x50348750   # ekern.exe code span
ANCHORS = [(0x6bb8, 0x80006bb8), (0x4ac, 0x503a5f0c)]  # trace-observed globals


def load_sdram(path: Path) -> bytes:
    """ram_ is the 16MB blob after a u64 size marker; verify by finding the
    kernel L1 page table inside (I/O section signature)."""
    blob = path.read_bytes()
    marker = struct.pack('<Q', SDRAM_SIZE)
    pos = -1
    while True:
        pos = blob.find(marker, pos + 1)
        if pos < 0:
            break
        start = pos + 8
        if start + SDRAM_SIZE > len(blob):
            continue
        ram = blob[start:start + SDRAM_SIZE]
        if find_l1(ram) is not None:
            print(f'SDRAM found at file offset {start:#x} (L1 table verified)')
            return ram
    raise SystemExit('no SDRAM block with an L1 page table found')


def find_l1(ram) -> int | None:
    """Locate the active L1 table: 16KB-aligned, section entries mapping
    VA 0x58000000->PA 0x0c000000 and VA 0x58100000->PA 0x0c100000
    (verified against the live-phone page map in docs/references.md)."""
    for base in range(0, SDRAM_SIZE - 0x4000, 0x4000):
        e0, e1 = struct.unpack_from('<II', ram, base + 0x580 * 4)
        if (e0 & 0xfff00003) == 0x0c000002 and (e1 & 0xfff00003) == 0x0c100002:
            return base
    return None


def words(ram, off, n):
    return struct.unpack_from('<%dI' % n, ram, off)


L1_BASE = None
_RAM = None
_tlb = {}


def va_off(va):
    """VA -> SDRAM offset via the checkpointed MMU tables (sections + small
    pages; coarse L2). Returns None when unmapped or not in SDRAM."""
    page = va >> 12
    if page in _tlb:
        base = _tlb[page]
        return None if base is None else base | (va & 0xfff)
    pa = None
    e = struct.unpack_from('<I', _RAM, L1_BASE + ((va >> 20) & 0xfff) * 4)[0]
    kind = e & 3
    if kind == 2:                                   # section
        pa = (e & 0xfff00000) | (va & 0x000fffff)
    elif kind == 1:                                 # coarse L2
        l2pa = e & 0xfffffc00
        if SDRAM_PA <= l2pa < SDRAM_PA + SDRAM_SIZE:
            l2e = struct.unpack_from(
                '<I', _RAM,
                (l2pa - SDRAM_PA) + ((va >> 12) & 0xff) * 4)[0]
            if l2e & 3 in (2, 3):                   # small/tiny page
                pa = (l2e & 0xfffff000) | (va & 0xfff)
            elif l2e & 3 == 1:                      # large page
                pa = (l2e & 0xffff0000) | (va & 0xffff)
    if pa is not None and SDRAM_PA <= pa < SDRAM_PA + SDRAM_SIZE:
        off = pa - SDRAM_PA
        _tlb[page] = off & ~0xfff
        return off
    _tlb[page] = None
    return None


def read_name(ram, ptr, max_len=80):
    """Dereference a candidate kernel name pointer: HBufC-style (length word
    then bytes) or bare c-string; returns a printable name or None."""
    off = va_off(ptr)
    if off is None or off + 8 > SDRAM_SIZE:
        return None
    # HBufC8: TDes header word, low 28 bits = length
    hdr = struct.unpack_from('<I', ram, off)[0]
    for body, length in ((off + 4, hdr & 0x0fffffff), (off, None)):
        if length is not None and not (1 <= length <= max_len):
            continue
        end = body + (length if length is not None else max_len)
        if end > SDRAM_SIZE:
            continue
        raw = ram[body:end]
        if length is None:
            nul = raw.find(b'\0')
            if nul < 1:
                continue
            raw = raw[:nul]
        if len(raw) >= 2 and all(0x20 <= b < 0x7f for b in raw):
            return raw.decode('ascii', 'replace')
    return None


def scan_objects(ram):
    """Find DObject candidates in the kernel home section: words whose value
    lies in ekern code, keyed by that (vtable) value; offsets are VAs."""
    objs = {}
    for mb in range(0, 16):                 # walk VA 0x80000000..0x81000000
        for page in range(0, 0x100000, 0x1000):
            va = KHOME_VA + mb * 0x100000 + page
            off = va_off(va)
            if off is None:
                continue
            for i in range(0, 0x1000, 4):
                v = struct.unpack_from('<I', ram, off + i)[0]
                if EKERN_LO <= v < EKERN_HI:
                    objs.setdefault(v, []).append(va + i)
    return objs


def describe(ram, va, vptr):
    w = [0] * 24
    for i in range(24):
        o = va_off(va + i * 4)
        w[i] = struct.unpack_from('<I', ram, o)[0] if o is not None else 0
    name = None
    for i in range(1, 24):
        name = read_name(ram, w[i])
        if name:
            break
    smalls = [f'{i * 4:#x}={w[i]}' for i in range(1, 12) if w[i] < 64]
    ptrs = [f'{i*4:#x}->{w[i]:08x}' for i in range(1, 16)
            if va_off(w[i]) is not None]
    return va, name, smalls, ptrs


def main():
    args = sys.argv[1:]
    if not args:
        raise SystemExit(__doc__)
    path = Path(args[0])
    ram = load_sdram(path)
    global _RAM, L1_BASE
    _RAM = ram
    L1_BASE = find_l1(ram)
    print(f'L1 page table at SDRAM offset {L1_BASE:#x} (PA {SDRAM_PA+L1_BASE:#x})')
    for va, want in ((0x80006bb8, 0x80006bb8), (0x800004ac, 0x503a5f0c)):
        off = va_off(va)
        got = struct.unpack_from('<I', ram, off)[0] if off is not None else None
        print(f'  anchor [{va:#x}] -> {got:#010x}' if got is not None
              else f'  anchor [{va:#x}] unmapped', '(expected %#x)' % want)

    if '--dump' in args:
        va = int(args[args.index('--dump') + 1], 16)
        off = va_off(va)
        if off is None:
            raise SystemExit('VA outside kernel home section')
        for row in range(0, 0x100, 16):
            w = words(ram, off + row, 4)
            print(f'{va+row:08x}: ' + ' '.join(f'{x:08x}' for x in w))
        return

    objs = scan_objects(ram)
    only = None
    if '--vtable' in args:
        only = int(args[args.index('--vtable') + 1], 16)

    # rank vtable groups: those whose members mostly have names are object
    # containers worth reading; print named groups first
    report = []
    for vptr, offs in objs.items():
        if only is not None and vptr != only:
            continue
        if len(offs) > 400:        # literal pools / non-objects
            continue
        rows = [describe(ram, off, vptr) for off in offs]
        named = [r for r in rows if r[1]]
        report.append((vptr, offs, rows, named))
    report.sort(key=lambda r: (-len(r[3]), len(r[1])))

    for vptr, offs, rows, named in report[:40]:
        if not named and only is None:
            continue
        print(f'\n== vtable {vptr:08x}: {len(offs)} instance(s), '
              f'{len(named)} named ==')
        for va, name, smalls, ptrs in rows[:20]:
            print(f'  obj {va:08x} name={name!r}')
            if smalls:
                print(f'      small-int fields: {", ".join(smalls)}')
            if ptrs and (only is not None or name):
                print(f'      kernel ptrs: {", ".join(ptrs[:8])}')


if __name__ == '__main__':
    main()
