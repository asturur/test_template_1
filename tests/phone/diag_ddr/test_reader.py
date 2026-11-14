"""Offline checks of the exact DDR writer output and torn/overwritten records."""
import importlib.util
import struct
from pathlib import Path

root = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('diag', root / 'tools/ngage_runtime_diag.py')
diag = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diag)
for name in ('guard.bin', 'guard-wrap.bin'):
    raw = bytearray((root / 'build/sim/unit-diag-ddr' / name).read_bytes())
    reader = diag.Reader(raw)
    events = reader.poll()
    text = [e for e in events if e['type'] == 'text']
    snap = [e for e in events if e['type'] == 'snapshot']
    assert len(text) == len(snap) == 1
    assert text[0]['text'] == 'ABCDEFGHIJKL'
    assert snap[0]['values']['fetch_pc'] == 0xABC00000
    assert snap[0]['save_progress']['lba'] == 0x12345678
    assert snap[0]['save_progress']['flags_hex'] == '0xabcdef00'
    assert snap[0]['save_queue'] == dict(count=8320, initialized=True,
        fault=True, flush_error=True, flushing=False, in_flight=False,
        mark_pending=False, head_ready=False, overflow=True,
        invalid_sector=False, raw_hex='0x514101c2')
    # Decode passive production-chip status, gated by its explicit marker.
    observed = bytearray(raw)
    for pos in (0xF000+30*4, 0xF400+30*4):
        struct.pack_into('<I', observed, pos, 0x80000000 | (0x8fff << 9))
    b = [e for e in diag.Reader(observed).poll() if e['type'] == 'snapshot'][0]['bringup']
    assert b['adsp_state'] == 15 and b['adsp_test42_seen']
    assert b['adsp_test42_complete'] and b['adsp_test42_ok'] and b['adsp_test42_acked']
    assert b['sim_present'] and not b['sim_overflow'] and not b['sim_busy']
    for pos in (0xF000+30*4, 0xF400+30*4):
        struct.pack_into('<I', observed, pos, 0x1ff)
    assert 'bringup' not in [e for e in diag.Reader(observed).poll() if e['type'] == 'snapshot'][0]
    # Older snapshots leave the extension word zero; they remain readable.
    legacy = bytearray(raw)
    for pos in (0xF000+244*4, 0xF400+244*4):
        struct.pack_into('<I', legacy, pos, 0)
    old = [e for e in diag.Reader(legacy).poll() if e['type'] == 'snapshot']
    assert len(old) == 1 and 'save_queue' not in old[0]
    assert snap[0]['panic']['valid_mask'] == 0, 'cold reset clears panic validity'
    assert reader.poll() == [], 'duplicate output'
    # A torn mailbox is ignored even when its magic/version look right.
    for pos in (0xF000+1020, 0xF400+1020):
        raw[pos:pos+4] = bytes(4)
    assert not any(e['type'] == 'snapshot' for e in diag.Reader(raw).poll())
    # Advance beyond ring capacity: warn of reader loss; retain raw bytes.
    h = diag.words(raw[:32]); seq = h[3] + h[2] + 2
    slot = seq % h[2]
    struct.pack_into('<8I', raw, 0x100+slot*32, seq, 123, 1, 0x58, 0, 0, 9, seq ^ diag.TEXT_SEAL)
    struct.pack_into('<I', raw, 12, seq)
    events = reader.poll()
    assert any(e['type'] == 'reader_gap' for e in events)
    assert [e['raw_hex'] for e in events if e['type'] == 'text'] == ['58']
    # A seal changed during the copy is never accepted.
    class Torn(diag.Reader):
        def read(self, offset, size):
            result = super().read(offset, size)
            if offset == 0x100+slot*32 and size == 32:
                self.memory[offset+28:offset+32] = bytes(4)
            return result
    assert not any(e['type'] == 'text' for e in Torn(raw).poll())
print('PASS DDR reader: writer output, deduplication, torn snapshots/text, wrap gaps and raw bytes')

# Incremental polling must not touch1024 already-consumed uncached slots.
class CountReads(diag.Reader):
    def __init__(self, memory):
        super().__init__(memory)
        self.text_reads = 0
    def sealed(self, offset, size, *args, **kwargs):
        if size == 32:
            self.text_reads += 1
        return super().sealed(offset, size, *args, **kwargs)

def ring(seed):
    raw = bytearray(65536)
    struct.pack_into('<8I', raw, 0, diag.TEXT_MAGIC, 1, 1024, 0, 0, seed, 78000000, 32)
    return raw

def publish(raw, seq, valid=True):
    struct.pack_into('<8I', raw, 0x100+(seq%1024)*32,
        seq, 123, 1, 0x58, 0, 0, 0, (seq ^ diag.TEXT_SEAL) if valid else 0)
    struct.pack_into('<I', raw, 12, seq)

for seed in (1, diag.TEXT_SEAL-1, 0xffffffff):
    raw = ring(seed)
    publish(raw, seed)
    reader = CountReads(raw)
    assert [e['sequence'] for e in reader.poll() if e['type'] == 'text'] == [seed]
    assert reader.text_reads == 1
    reader.text_reads = 0
    assert reader.poll() == [] and reader.text_reads == 0
    next_seq = diag.advance(seed)
    publish(raw, next_seq, valid=False)
    assert not any(e['type'] == 'text' for e in reader.poll())
    assert reader.last_text == seed, 'torn final record must be retried'
    publish(raw, next_seq)
    reader.text_reads = 0
    assert [e['sequence'] for e in reader.poll() if e['type'] == 'text'] == [next_seq]
    assert reader.text_reads == 1, 'skip reserved seal/zero sequence values'
print('PASS incremental reader: idle/new-only reads, torn-tail retry, seal and32-bit wrap')
