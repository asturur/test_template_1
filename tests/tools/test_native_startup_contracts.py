"""Unmodified NEM-4 startup clients: required RF/ADSP transactions.

Only allocation, message transport, timers and debug leaves are spied. This
identifies client contracts; it does not qualify a peripheral implementation.
Synthetic responses are test inputs, never production firmware substitutions.
"""
import hashlib
from pathlib import Path
import struct
from unicorn import Uc, UC_ARCH_ARM, UC_MODE_ARM, UC_HOOK_CODE
from unicorn.arm_const import *

ROOT = Path(__file__).resolve().parents[2]
NOS = (ROOT/'firmware/THC N-Gage ROM Dump/ngage-gsmstuff-0x5149D280.dll').read_bytes()
assert hashlib.sha256(NOS).hexdigest() == 'e5870e918c90d9c7a6403eb0ee305d174e906aeae0a7fa8069e85a18aeec7aa1'
BODY = NOS[96:]
BASE, STOP, OUT, MESSAGE = 0x5149d280, 0x51400000, 0x80100100, 0x80101000

def literal(address):
    return struct.unpack_from('<I', BODY, address-BASE)[0]

STATE = literal(0x5164ab48)
RESPONSE = literal(0x5164ab30)


def fixture():
    u = Uc(UC_ARCH_ARM, UC_MODE_ARM)
    u.mem_map(0x51400000, 0x400000)
    u.mem_write(BASE, BODY)
    u.mem_map(0x80000000, 0x110000)
    u.reg_write(UC_ARM_REG_CPSR, 0x13)
    u.reg_write(UC_ARM_REG_SP, 0x8010f000)
    sent, timers, freed, lengths = [], [], [], []
    def hook(u, address, size, data):
        if address == STOP:
            u.emu_stop()
            return
        if address == 0x514b9a44:
            size = u.reg_read(UC_ARM_REG_R0)
            assert size in (4, 8)
            u.mem_write(MESSAGE, bytes(size))
            u.reg_write(UC_ARM_REG_R0, MESSAGE)
        elif address == 0x514ba3f0:
            sent.append((u.reg_read(UC_ARM_REG_R0), u.reg_read(UC_ARM_REG_R1),
                         bytes(u.mem_read(u.reg_read(UC_ARM_REG_R2), 8))))
            u.reg_write(UC_ARM_REG_R0, 0)
        elif address == 0x5164ab64:
            timers.append(u.reg_read(UC_ARM_REG_R0))
        elif address == 0x514b9ab4:
            freed.append(u.reg_read(UC_ARM_REG_R0))
        elif address == 0x5152fc7c:
            pass  # Native debug entry; not a peripheral completion.
        elif address == 0x5152fc9c:
            lengths.append(tuple(u.reg_read(r) for r in (UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_R2)))
        else:
            return
        u.reg_write(UC_ARM_REG_PC, u.reg_read(UC_ARM_REG_LR))
    u.hook_add(UC_HOOK_CODE, hook)
    return u, sent, timers, freed, lengths


def call(u, entry):
    u.reg_write(UC_ARM_REG_R0, OUT)
    u.reg_write(UC_ARM_REG_LR, STOP | 1)
    for reg, value in ((UC_ARM_REG_R4, 4), (UC_ARM_REG_R5, 5)):
        u.reg_write(reg, value)
    u.emu_start(entry | 1, 0, count=20000)
    assert u.reg_read(UC_ARM_REG_PC) == STOP
    assert u.reg_read(UC_ARM_REG_SP) == 0x8010f000
    assert u.reg_read(UC_ARM_REG_R4) == 4 and u.reg_read(UC_ARM_REG_R5) == 5
    # The emulator did not modify or replace any guest instruction.
    assert bytes(u.mem_read(BASE, len(BODY))) == BODY
    return u.reg_read(UC_ARM_REG_R0)


for entry, resource, expected, timeout in (
    (0x516a60c0, 0x1b, bytes.fromhex('0c070020'), 500),
    (0x516a6218, 0x82, bytes.fromhex('0e2b00070042'), 3000),
):
    u, sent, timers, freed, lengths = fixture()
    u.mem_write(OUT, b'\xcc')
    assert call(u, entry) == 2, 'first phase must remain pending'
    assert len(sent) == 1 and sent[0][0:2] == (resource, 0x80009d20)
    assert sent[0][2][:len(expected)] == expected
    assert timers == [timeout]
    assert u.mem_read(OUT, 1) == b'\xcc'
    assert u.mem_read(STATE, 1) == b'\1'
    if resource == 0x82:
        assert lengths == [(8, 0, MESSAGE)]
    # A timeout is a real failed result. Do not disable the registry entry.
    u.mem_write(STATE, b'\xff')
    assert call(u, entry) == 0
    assert bytes(u.mem_read(OUT, 1)) == bytes((13 if resource == 0x1b else 1,))
    assert not freed

# RF ID54 is a subblock, not an ASCII T marker. Use the native builder layout.
# The synthetic revision03 is the explicit modeled device identity.
for packet, expected in (
    (bytes.fromhex('0c0800015408000330330000'), 0),
    (bytes.fromhex('0c0800015508000330330000'), 1),
    (bytes.fromhex('0c0800005408000330330000'), 1),
    (bytes.fromhex('0c0800015408000330340000'), 1),
):
    u, sent, timers, freed, lengths = fixture()
    u.mem_write(STATE, b'\1')
    u.mem_write(RESPONSE, struct.pack('<I', MESSAGE))
    u.mem_write(MESSAGE, packet)
    assert call(u, 0x516a60c0) == 0
    assert bytes(u.mem_read(OUT, 1)) == bytes((expected,))
    assert freed == [MESSAGE] and not sent

# ADSP reports the actual returned diagnostic result; nonzero must fail.
for result in (0, 1, 0x1234):
    u, sent, timers, freed, lengths = fixture()
    u.mem_write(STATE, b'\1')
    u.mem_write(RESPONSE, struct.pack('<I', MESSAGE))
    u.mem_write(MESSAGE, bytes.fromhex('0e8b00070042') + struct.pack('<H', result))
    assert call(u, 0x516a6218) == 0
    assert bytes(u.mem_read(OUT, 1)) == bytes((int(result != 0),))
    assert freed == [MESSAGE] and not sent

print('PASS unmodified native RF/ADSP clients: pending requests, timers, response validation, failure propagation, release and unchanged ROM')
