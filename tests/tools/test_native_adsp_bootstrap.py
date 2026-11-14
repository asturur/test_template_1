"""Execute original ARM ADSP link-start handling on recovered D550 packets.

D550 constructors448CDA/448C33 are recovered from the audited C55x image,
called in that order by RAM03FCA4. ARM checksum/constructor/receive-branch
instructions are unchanged. Descriptor/allocator/delay/send leaves are fixture
services, not a kernel scheduler or UART/physical reset qualification.
"""
from pathlib import Path
import hashlib
import struct
from unicorn import *
from unicorn.arm_const import *
ROOT = Path(__file__).resolve().parents[2]
r = (ROOT / 'build/firmware/nem4-factory/core.bin').read_bytes()
assert hashlib.sha256(r).hexdigest() == 'be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524'
u = Uc(UC_ARCH_ARM, UC_MODE_ARM)
u.mem_map(0x50000000, 0x1400000)
u.mem_write(0x50000000, r)
u.mem_map(0x80000000, 262144)
u.mem_map(0x400000, 4096)
stop = 0x80000000
host = stop + 256
rx = stop + 1024
payload = stop + 2048
heap = stop + 0x10000
sent = []

def word(a, v):
    u.mem_write(a, struct.pack('<I', v))

def rd(a):
    return struct.unpack('<I', u.mem_read(a, 4))[0]

def desc(a, p, n):
    u.mem_write(a, struct.pack('<III', 0x20000000 | n, 1024, p))

def data(a):
    return bytes(u.mem_read(rd(a + (4 if rd(a) >> 28 == 1 else 8)), rd(a) & 0xfffffff))

def append(a, b):
    n = rd(a) & 0xfffffff
    u.mem_write(rd(a + 8) + n, b)
    word(a, 0x20000000 | (n + len(b)))

def hook(c, a, n, d):
    global heap
    if a in (stop, 0x510ecc8c):
        c.emu_stop()
        return
    x = [c.reg_read(q) for q in (UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_R2, UC_ARM_REG_R3)]
    if a == 0x510ef7cc:
        c.reg_write(UC_ARM_REG_R0, heap)
        heap += 1024
    elif a == 0x510ef970:
        desc(x[0], 0, 0)
    elif a == 0x510ef988:
        word(heap, x[0])
        c.reg_write(UC_ARM_REG_R0, heap)
        heap += 1024
    elif a == 0x510ef808:
        desc(x[0], x[1] + 4, 0)
    elif a == 0x510ef6bc:
        append(x[0], bytes([x[1] & 255]))
    elif a == 0x510ef844:
        append(x[0], data(x[1]))
    elif a == 0x510ef5f0:
        c.reg_write(UC_ARM_REG_R0, rd(x[0] + 8) + x[1])
    elif a == 0x510ef9a0:
        c.reg_write(UC_ARM_REG_R0, rd(x[0] + 8))
    elif a == 0x510ef994:
        # TPtrC8 occupies eight bytes; TPtr8 above occupies twelve.
        b = bytes(c.mem_read(x[1], 32)).split(b'\x00')[0]
        u.mem_write(x[0], struct.pack('<II', 0x10000000 | len(b), x[1]))
    elif a == 0x510ef8d4:
        assert x[0] == 200
    elif a == stop + 4:
        sent.append(data(x[1] + 4))
    else:
        return
    c.reg_write(UC_ARM_REG_PC, c.reg_read(UC_ARM_REG_LR))
u.hook_add(UC_HOOK_CODE, hook)

def call(a, *args):
    initial = [(UC_ARM_REG_CPSR, 0x13), (UC_ARM_REG_SP, 0x8000f000),
               (UC_ARM_REG_LR, stop | 1)]
    initial += list(zip((UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_R2, UC_ARM_REG_R3), args))
    for q, v in initial:
        u.reg_write(q, v)
    u.emu_start(a | 1, 0, count=10000)
    assert u.reg_read(UC_ARM_REG_PC) == stop, hex(u.reg_read(UC_ARM_REG_PC))

def packet(raw):
    desc(rx + 4, payload, len(raw))
    u.mem_write(payload, raw)
    word(rx + 16, 6 + int.from_bytes(raw[4:6], 'big') - 2)
BOOT = bytes.fromhex('5555200078d000040111016058a5')
RESET = bytes.fromhex('5555200078d00003040160003cd2')
REPLY = bytes.fromhex('5555207800d000030501400065aa')

def verify(raw):
    packet(raw)
    call(0x510edc6c, rx)
    return u.reg_read(UC_ARM_REG_R0)
# Original checksum verification independently rejects corruption in every byte.
for frame in (BOOT, RESET, REPLY):
    raw = frame[2:]
    assert verify(raw) == 1
    for i in range(len(raw)):
        corrupt = bytearray(raw)
        corrupt[i] ^= 1
        assert verify(bytes(corrupt)) == 0, (frame.hex(), i)
word(host + 0x74, host + 0x200)
word(host + 0x200, host + 0x240)
word(host + 0x250, stop + 5)

# Start at the original D0 resource/subtype branch after frame decoding. The fixture
# stops before shared cleanup; it does not execute the kernel scheduler.
def receive(raw):
    packet(raw)
    for q, v in [(UC_ARM_REG_CPSR, 0x13), (UC_ARM_REG_SP, 0x8000f000),
                 (UC_ARM_REG_LR, stop | 1), (UC_ARM_REG_R5, host),
                 (UC_ARM_REG_R6, rx + 4)]:
        u.reg_write(q, v)
    word(0x8000f00c, rx)
    u.emu_start(0x510ecba7, 0, count=10000)
    assert u.reg_read(UC_ARM_REG_PC) == 0x510ecc8c
    assert u.reg_read(UC_ARM_REG_SP) == 0x8000f000
# The D550 announcement alone must not make the fresh host ready.
receive(BOOT[2:])
assert rd(host + 0x14) == 0 and (not sent)
for pending in (0, 1):
    word(host + 0x14, 0)
    word(host + 0x94, pending)
    u.mem_write(host + 0x7c, b'\x07')
    before = len(sent)
    receive(RESET[2:])
    assert len(sent) == before + 1 and sent[-1] == REPLY
    assert rd(host + 0x14) == 1
    assert bytes(u.mem_read(host + 0x7c, 1)) == bytes([1 + pending])
    if pending:
        assert rd(host + 0x94) == 0
    assert rd(host + 0xa4) == 0xffffffff
    receive(RESET[2:])
    assert sent[-1] == REPLY and rd(host + 0x14) == 1
    assert bytes(u.mem_read(host + 0x7c, 1)) == b'\x01'
assert bytes(u.mem_read(0x50000000, len(r))) == r
print('PASS original ADSP startup: D550 D0/01 then D0/04, checksum/corruption rejection, exact D0/05, link-ready/sequence reset, pending reset and repeated D0/04; ROM unchanged')
