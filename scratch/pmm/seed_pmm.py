#!/usr/bin/env python3
"""Seed image for the simulated N-Gage PMM (CS0 physical 0x7f0000..0x7fffff, 64 KiB).

Usage: seed_pmm.py [-o pmm-seed.bin] [--date YYYY-MM-DD] [--rec1 zero|same|next]

Output: 65536 bytes, 0xFF everywhere except the formatted sector headers and
three NVD records (table 0xd4, ids 0,1,2; 8-byte payloads).  Offsets are
relative to PA 0x7f0000 (the NOS reaches it through the MMU; the VA used was
not checked).  Flash only clears bits (1->0): every value below is written as
the NOS would program it, so a later NOS write can still clear more bits.

FORMAT (NOS image build/firmware/thc/nos-image.bin, Thumb, base 0x5149d280)
-------------------------------------------------------------------------
Flash descriptor table at 0x51712a74 (12-byte entries {base,size,count|slot<<8|
chip<<16|type<<24}) is PROVEN to exist; the entry used is chosen by the flash ID
(Hw_pmm id switch 0x515b659c: manufacturer 1 / device 0x257e -> type 4, PROVEN
from the code; the sim's amd16 profile reports 0x257e).  Type 4 entries:
    region a (slot 0): base 0x7f0000, sector 0x4000, 2 sectors  (0x7f0000,0x7f4000)
    region c (slot 2): base 0x7f8000, sector 0x4000, 2 sectors  (0x7f8000,0x7fc000)
  (type 3 would be 8 KiB sectors at the same base; type 5 is at 0x1ff0000.
   If the sim reports another ID the sector size changes: INFERRED=amd16.)

Sector header (written by the PMM format routine 0x514beb4c; PROVEN by reading
the writer, not by observing a flash dump):
    +0x00 u16 0xF0F0     idle/erase mark (reader 0x514be2dc, 0x514bebd0 demand F0F0 or FFFF)
    +0x02 u16 state      staircase, each state clears one more bit:
                         1=0xFFFE 2=0xFFFC 4=0xFFF8 ... (decoder 0x514be578; writer 0x514be408)
    +0x04 u16 2          } written by 0x514be630 with PMMCAT; the NOS's own
    +0x06 "PMMCAT"       } first sector of each region only
    +0x0C u32 1          sector erase counter
    +0x10 u16 0
    +0x12 u16 region (0 for a, 2 for c)
    +0x18 u16 2
  First sector of a region ends at state 4 (0xFFF8); the other sectors are only
  F0F0 / counter 1 / state 1 (0xFFFE).  Scan (0x515c7a30) walks only sectors of
  state 2, 4 or 0x10 and starts at sector+0x20.

Record (12-byte header + payload), chain located by 0x515c8e88 / 0x515cb504:
    +0x00 u8  state     byte-staircase (decoder 0x515ca3e4): FF=0 FE=1 FC=2 F8=4
                        F0=8 E0=0x10 C0=0x20 80=0x40 00=0x80.  NVD read accepts
                        4,8,0x10,0x20,0x80 (0x5152bbc8); the startup scan keeps 8,
                        0x10, 0x20 (jump table 0x515c7ec4 / 0x515c74a4).  We use 8 (0xF0).
    +0x01 u8  table id  (0xd4; reader maps via 0x800ce978, writer via 0x8000bac0)
    +0x02 u16 record id
    +0x04 u16 0xFFFF    unknown (free-slot test at 0x515c9020 wants FFFF in unused headers)
    +0x05 u8  0xFF      NOTE overlaps +0x04: byte5 = fragment link (FF = none); 0xFFFF keeps it FF
    +0x08 u16 payload length (!= 0xFFFF required, 0x5152bba8 / 0x515cbcfc)
    +0x0A u16 offset-in-sector of the NEXT record header (0x515cb504); 0xFFFF only
              passes if the record ends at the very end of the sector
    +0x0C     payload
  No CRC/checksum was found in the read, scan or validate paths (0x5152ba5c,
  0x515c7a30, 0x515cbcb8).  Records are packed back to back from sector+0x20.

NOT PROVEN / uncertain:
  * No real PMM dump exists; none of this was seen in a phone or sim trace.
  * Flash chip type -> sector size (see above).  Bytes +4/+6/+7 of a record
    header are unknown (left FF).  Whether the NOS requires the other three
    sectors to be formatted (we mirror its format routine) is unverified.
  * Whether byte0=0xF0 survives the later passes unchanged (they may clear bit 6).

TTime VALUES (ecust 0x5034e138, PROVEN from the disassembly)
-------------------------------------------------------------
  0x503502d8 -> 0x503a3d90 = TTime operator!= (returns 1 if differ);
  0x503502e4 -> 0x503a3d74 = TTime operator==.
  Accept requires  a == b  AND  a != TTime(0), where (dispatcher 0x5034e444
  op 1) a=*r2, b=*r3, c=*[sp+0x2c] and the NOS passes (rec2, rec0, rec1)
  through 0x516c77b4 -> 0x514a6438 -> 0x514a4d64 unchanged (identity copies).
  So a=rec2, b=rec0, c=rec1: rec2 MUST equal rec0 and be nonzero.  rec1 (c) is
  free: 0 skips the "c != 0" conversion path (0x5034e220), which has not been
  traced; --rec1 same sets it equal to a.  (Argument order is INFERRED from
  thunk/wrapper code reading, the a==b rule is PROVEN.)
  TTime = signed 64-bit microseconds since 0000-01-01 (Symbian; 2000-01-01 =
  63113904000000000), stored little-endian (low word first).
  ecust builds "now" from base=midnight(a) plus RTC day counter/h/m/s
  (0x5034f728, 0x5034f820), so RTC day=1, 00:00:00 means now = date(a)+1 day.
"""
import argparse
import datetime
import struct

PMM_SIZE = 0x10000
SECTOR = 0x4000
TABLE_ID = 0xD4
HDR = 0x20          # first record offset inside a sector
REC_HDR = 0xC


def ttime_us(d: datetime.date) -> int:
    days = d.toordinal() - 1 + 366          # 0000-01-01 is day 0 (year 0 is leap)
    return days * 86400 * 1_000_000


def put16(img, off, v):
    img[off:off + 2] = struct.pack('<H', v)


def put32(img, off, v):
    img[off:off + 4] = struct.pack('<I', v)


def format_sector(img, base, first, region):
    put16(img, base + 0x00, 0xF0F0)
    put32(img, base + 0x0C, 1)
    if not first:
        put16(img, base + 0x02, 0xFFFF & ~1)
        return
    put16(img, base + 0x02, 0xFFFF & ~1 & ~2 & ~4)
    put16(img, base + 0x04, 2)
    img[base + 0x06:base + 0x0C] = b'PMMCAT'
    put16(img, base + 0x10, 0)
    put16(img, base + 0x12, region)
    put16(img, base + 0x18, 2)


def build(date, rec1_mode, values=None):
    img = bytearray(b'\xff' * PMM_SIZE)
    for region, first_sector in ((0, 0), (2, 2)):
        format_sector(img, first_sector * SECTOR, True, region)
        format_sector(img, (first_sector + 1) * SECTOR, False, region)

    t = ttime_us(date)
    # 'next': c = a + 1 day. ecust 0x5034e7d8 exits unchanged when c == now and
    # needs c - now to be whole days (hour/min 0) for state 2 (observed in sim).
    nxt = t + 86400 * 1000000
    payload = {0: t, 2: t, 1: {'same': t, 'next': nxt}.get(rec1_mode, 0)}
    if values:
        m = {'a': t, 'n': nxt, '0': 0}
        payload = {i: m[v] for i, v in enumerate(values.split(','))}
    off = HDR
    for rid in (0, 1, 2):
        end = off + REC_HDR + 8
        h = bytearray(b'\xff' * REC_HDR)
        h[0] = 0xF0
        h[1] = TABLE_ID
        put16(h, 2, rid)
        put16(h, 8, 8)
        put16(h, 0x0A, end)
        img[off:off + REC_HDR] = h
        img[off + REC_HDR:end] = struct.pack('<Q', payload[rid])
        off = end
    return img, payload


def verify(img, payload):
    off = HDR
    seen = {}
    while img[off + 1] != 0xFF:
        state, tbl = img[off], img[off + 1]
        rid, = struct.unpack_from('<H', img, off + 2)
        ln, nxt = struct.unpack_from('<HH', img, off + 8)
        assert state == 0xF0 and tbl == TABLE_ID and ln == 8 and nxt != 0xFFFF
        seen[rid], = struct.unpack_from('<Q', img, off + REC_HDR)
        off = nxt
    assert seen == payload, (seen, payload)
    assert any(seen.values())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-o', '--output', default='pmm-seed.bin')
    ap.add_argument('--date', default='2004-06-01',
                    help='date whose 00:00:00 is rec0/rec2 (a==b)')
    ap.add_argument('--values', help='explicit rec0,rec1,rec2 each a|n|0 (a=date, n=date+1day)')
    ap.add_argument('--rec1', choices=('zero', 'same', 'next'), default='next')
    args = ap.parse_args()
    d = datetime.date.fromisoformat(args.date)
    img, payload = build(d, args.rec1, args.values)
    verify(img, payload)
    assert len(img) == PMM_SIZE
    with open(args.output, 'wb') as f:
        f.write(img)
    print(f'{args.output}: {len(img)} bytes, TTime(a)=0x{payload[0]:016x} ({d} 00:00:00)')


if __name__ == '__main__':
    main()
