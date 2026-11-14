"""Unchanged current-consumption startup client, not a UEM implementation.

Synthetic energy replies expose the original retry/sentinel contract. Allocator,
transport and timer leaves are spied. No response is installed on MiSTer.
"""
import runpy
import struct
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
n = runpy.run_path(str(ROOT/'tests/tools/test_native_startup_contracts.py'))
entry = 0x516a5ebc
cases = 0
for status, value in ((1, 0), (1, 0x7ffc), (1, 0x7ffd), (1, 0x7ffe),
                      (1, 0x7fff), (1, 0x8000), (0, 0), (2, 0)):
    u, sent, timers, freed, lengths = n['fixture']()
    out, state, message = n['OUT'], n['STATE'], n['MESSAGE']
    u.mem_write(out, b'\xcc')
    assert n['call'](u, entry) == 2
    assert sent[0][:2] == (0x17, 0x80009d20)
    assert sent[0][2][:4] == bytes.fromhex('0a110f01') and timers == [200]
    assert bytes(u.mem_read(state, 1)) == b'\1'
    def reply():
        u.mem_write(n['RESPONSE'], struct.pack('<I', message))
        u.mem_write(message, bytes((0x0a, 0x12, status, 0)) + value.to_bytes(4, 'big'))
    reply()
    retry = status == 0 or (status == 1 and 0x7ffd <= value <= 0x7fff)
    assert n['call'](u, entry) == (2 if retry else 0)
    assert freed == [message]
    if retry:
        assert bytes(u.mem_read(state, 1)) == b'\1'
        assert bytes(u.mem_read(n['literal'](0x5164ab54), 1)) == b'\2'
        # Fixture delivers the timer's requested phase transition. This does
        # not run or qualify the RTOS timer/scheduler.
        u.mem_write(state, b'\2')
        assert bytes(u.mem_read(out, 1)) == b'\xcc'
        assert n['call'](u, entry) == 2
        assert len(sent) == 2 and sent[1][:2] == sent[0][:2] and sent[1][2][:4] == sent[0][2][:4] and timers == [200, 200, 200]
        assert bytes(u.mem_read(state, 1)) == b'\3'
        reply()
        assert n['call'](u, entry) == 0
        assert bytes(u.mem_read(out, 1)) == b'\1'
        assert freed == [message, message]
    else:
        assert bytes(u.mem_read(out, 1)) == bytes((int(status == 2),))
    cases += 1
u, sent, timers, freed, lengths = n['fixture']()
u.mem_write(n['STATE'], b'\xff')
assert n['call'](u, entry) == 0 and bytes(u.mem_read(n['OUT'], 1)) == b'\x0d'
print(f'PASS {cases} native current-consumption cases: resource17/request0A110F01, '
      '200 deadline, 7FFD..7FFF sentinel retry, result propagation, timeout0D; ROM unchanged')
