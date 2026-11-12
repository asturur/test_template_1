#!/usr/bin/env python3
"""Read ngage1 DDR diagnostics without writing memory or mounting a disk.

On MiSTer: python3 ngage_runtime_diag.py --follow
Over SSH: ssh root@MISTER 'python3 - --follow' < tools/ngage_runtime_diag.py
Offline: --file guard.bin (64 KiB beginning at physical 0x313f0000).
Output is JSONL, including raw text bytes and the complete NGD snapshot.
"""
import argparse
import json
import mmap
import os
import struct
import sys
import time

BASE, SIZE = 0x313F0000, 65536
TEXT_MAGIC, TEXT_SEAL = 0x3154474E, 0x4354474E
SNAP_MAGIC, SNAP_SEAL = 0x3244474E, 0x4344474E
NAMES = ('fetch_pc last_pc last_instruction cpsr cycles fetches bus_address '
         'bus_write_data bus_read_data bus_flags acks errors current_wait max_wait '
         'last_address last_data first_fault_address first_fault_pc first_fault_data '
         'first_fault_flags first_fault_reason boot_flags cpu_flags keys').split()


def words(raw):
    return struct.unpack('<%dI' % (len(raw) // 4), raw)


def distance(new, old):
    return (new - old) & 0xFFFFFFFF


def advance(value):
    value = (value + 1) & 0xFFFFFFFF
    while value in (0, TEXT_SEAL):
        value = (value + 1) & 0xFFFFFFFF
    return value


class Reader:
    def __init__(self, memory):
        self.memory = memory
        self.session = None
        self.last_text = None
        self.last_snapshot = None
        self.dropped = None

    def read(self, offset, size):
        return bytes(self.memory[offset:offset + size])

    def sealed(self, offset, size, magic=None, seal=TEXT_SEAL):
        before = self.read(offset + size - 4, 4)
        raw = self.read(offset, size)
        after = self.read(offset + size - 4, 4)
        w = words(raw)
        seq = w[2] if magic else w[0]
        if (before != after or raw[-4:] != before or w[-1] == 0
                or w[-1] != (seq ^ seal) or (magic and w[0] != magic)):
            return None
        return w, raw

    def poll(self):
        events = []
        hraw = self.read(0, 32)
        h = words(hraw)
        if (h[0] == TEXT_MAGIC and h[1] == 1 and h[2] in (8, 1024)
                and h[7] == 32 and h[5] not in (0, TEXT_SEAL)):
            session = (h[5], h[6], h[2])
            if session != self.session:
                self.session, self.last_text, self.dropped = session, None, None
                events.append(dict(type='session', first_sequence=h[5], clock_hz=h[6], capacity=h[2]))
            head, capacity = h[3], h[2]
            if head:
                # Read retained records in sequence order, restricting them to
                # this FPGA session and to the published head. Torn slots retry.
                records = []
                for slot in range(capacity):
                    result = self.sealed(0x100 + slot * 32, 32)
                    if not result:
                        continue
                    w, raw = result
                    seq = w[0]
                    if (seq % capacity != slot or distance(head, seq) >= capacity
                            or distance(seq, h[5]) >= 0x80000000
                            or not 1 <= (w[2] & 255) <= 12):
                        continue
                    if self.last_text is not None and distance(seq, self.last_text) not in range(1, 0x80000000):
                        continue
                    records.append((distance(head, seq), w, raw))
                # If header changed while reading, retry instead of joining
                # sessions or interpreting stale slots during FPGA reload.
                hend = words(self.read(0, 32))
                if hend[0:3] == h[0:3] and hend[5:] == h[5:]:
                    for _, w, raw in sorted(records, key=lambda r: -r[0]):
                        seq = w[0]
                        expected = advance(self.last_text) if self.last_text is not None else h[5]
                        if seq != expected:
                            events.append(dict(type='reader_gap', expected=expected, next_sequence=seq,
                                               sequence_distance=distance(seq, expected)))
                        n = w[2] & 255
                        payload = raw[12:12+n]
                        events.append(dict(type='text', sequence=seq, cycle=w[1], generation=w[2] >> 8,
                                           text=payload.decode('utf-8', errors='replace'), raw_hex=payload.hex(),
                                           dropped=w[6]))
                        self.last_text = seq
            if self.dropped != h[4]:
                events.append(dict(type='producer_drops', total=h[4]))
                self.dropped = h[4]
        snapshots = []
        for offset in (0xF000, 0xF400):
            result = self.sealed(offset, 1024, SNAP_MAGIC, SNAP_SEAL)
            if not result:
                continue
            w, raw = result
            if w[1] != 1 or w[7] != 406:
                continue
            snapshots.append((w, raw))
        if snapshots:
            w, raw = snapshots[0]
            if len(snapshots) == 2 and distance(snapshots[1][0][2], w[2]) < 0x80000000:
                w, raw = snapshots[1]
            identity = (w[2], w[240], w[241])
            if identity != self.last_snapshot:
                ngd = struct.unpack('<406H', raw[128:940])
                event = dict(type='snapshot', sequence=w[2], clock_hz=w[3], start_cycle=w[4],
                             end_cycle=w[5], reset_generation=w[6], values=dict(zip(NAMES, w[8:32])),
                             build_tag=((w[241] << 32) | w[240]).to_bytes(8, 'big').lstrip(b'\0').decode('ascii', errors='replace'),
                             ngd_halfwords=list(ngd))
                save_flags = ('mounted saved saving error manual_batch flush_pending tracker_pending '
                              'tracker_flushing tracker_valid flash_quiescent bridge_ready bridge_done '
                              'bridge_error host_ack host_read_request host_write_request ddr_request '
                              'ddr_ready ddr_done tracker_error tracker_fault bundle_verified '
                              'autosave_enabled autosave_paused dirty_event').split()
                event['save_progress'] = dict(state=w[242] & 7, slot=(w[242] >> 3) & 1,
                                              flags_hex=f'0x{w[242]:08x}', lba=w[243],
                                              **{name: bool(w[242] & (1 << bit))
                                                 for bit, name in enumerate(save_flags, 4)})
                if ngd[396] == 0x504E:
                    panic = struct.pack('<6H', *ngd[398:404])
                    event['panic'] = dict(valid_mask=ngd[397] & 7, payload_hex=panic.hex(),
                                          reason=struct.unpack('<I', panic[8:])[0])
                if ngd[404] == 0x5356:
                    event['save_errors'] = dict(c=bool(ngd[405] & 1), pmm=bool(ngd[405] & 2))
                events.append(event)
                self.last_snapshot = identity
        return events


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--file', help='64 KiB offline guard dump instead of /dev/mem')
    parser.add_argument('--follow', action='store_true')
    parser.add_argument('--interval', type=float, default=0.25)
    args = parser.parse_args()
    if args.interval < 0.01:
        parser.error('interval must be at least 0.01 seconds')
    fd = os.open(args.file or '/dev/mem', os.O_RDONLY | (0 if args.file else os.O_SYNC))
    try:
        with mmap.mmap(fd, SIZE, access=mmap.ACCESS_READ, offset=0 if args.file else BASE) as memory:
            reader = Reader(memory)
            first = True
            while True:
                events = reader.poll()
                for event in events:
                    print(json.dumps(event, ensure_ascii=True), flush=True)
                if first and not events:
                    print('No supported DDR diagnostics present; requires the new ngage1 RBF.', file=sys.stderr)
                first = False
                if not args.follow:
                    return 0 if events else 2
                time.sleep(args.interval)
    finally:
        os.close(fd)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        pass
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(2)
