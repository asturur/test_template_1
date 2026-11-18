"""Follow captured PCM requests and candidate replies through unchanged NEM-4 NOS."""
import hashlib
from pathlib import Path
import struct

from unicorn import UC_ARCH_ARM, UC_HOOK_CODE, UC_MODE_ARM, Uc
from unicorn.arm_const import (UC_ARM_REG_CPSR, UC_ARM_REG_LR, UC_ARM_REG_PC,
                               UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_SP)

ROOT = Path(__file__).resolve().parents[3]
ROM_BASE = 0x5149D280
RAM = 0x80000000
RETURN = 0x51400000
STACK = RAM + 0x1F0000
PACKET = RAM + 0x110000
POOL = RAM + 0x120000

original = (ROOT / 'firmware/THC N-Gage ROM Dump/ngage-gsmstuff-0x5149D280.dll').read_bytes()
assert hashlib.sha256(original).hexdigest() == (
    'e5870e918c90d9c7a6403eb0ee305d174e906aeae0a7fa8069e85a18aeec7aa1')
body = original[96:]
cpu = Uc(UC_ARCH_ARM, UC_MODE_ARM)
cpu.mem_map(RETURN, 0x400000)
cpu.mem_write(ROM_BASE, body)
cpu.mem_map(RAM, 0x200000)
enqueue = []
pool_next = POOL


def read(a, n):
    return bytes(cpu.mem_read(a, n))


def call(a, r0=0, r1=0):
    for reg, val in ((UC_ARM_REG_CPSR, 0x13), (UC_ARM_REG_SP, STACK),
                     (UC_ARM_REG_LR, RETURN | 1), (UC_ARM_REG_R0, r0), (UC_ARM_REG_R1, r1)):
        cpu.reg_write(reg, val)
    cpu.emu_start(a | 1, RETURN, count=50000)
    assert cpu.reg_read(UC_ARM_REG_PC) == RETURN, hex(cpu.reg_read(UC_ARM_REG_PC))
    return cpu.reg_read(UC_ARM_REG_R0)


def leaf(c, address, size, unused):
    global pool_next
    r0 = c.reg_read(UC_ARM_REG_R0)
    r1 = c.reg_read(UC_ARM_REG_R1)
    if address == 0x516C74FC:         # Stock pool ownership boundary.
        result = int(r0 in range(POOL, pool_next, 256))
    elif address == 0x516C750C:       # Stock pool allocation boundary.
        assert 0 < r0 < 256
        result = pool_next
        pool_next += 256
    elif address == 0x516C7504:       # Stock pool release boundary.
        assert r0 in range(POOL, pool_next, 256)
        result = 0
    elif address == 0x516C751C:       # Scheduled NOS tasks are the fixture boundary.
        size = int.from_bytes(read(r1+4, 2), 'little') + 6
        enqueue.append((r0, read(r1, size)))
        result = 1
    elif address == 0x514BC398:       # Link registry's task notification.
        result = 0
    else:
        return
    c.reg_write(UC_ARM_REG_R0, result)
    c.reg_write(UC_ARM_REG_PC, c.reg_read(UC_ARM_REG_LR))


cpu.hook_add(UC_HOOK_CODE, leaf)
# The immutable product table contains all five media records. Initialize
# the same pointer array consumed by the original forwarding routine.
cpu.mem_write(0x80009CF0, read(0x51713F38, 5*4))
assert read(0x516E7678, 12) == struct.pack('<III', 0x312, 0, 0x515BF06D)
assert read(0x516E7668, 4) == struct.pack('<I', 0x516E7640)
call(0x51530360)                         # Initialize original name tables.
assert call(0x51530558, 0xE8) == 0x7C01
# Feed the production MDI announcement to its original D0/04 handler.
cpu.mem_write(PACKET, bytes.fromhex('12007cd001000400'))
call(0x514BC06C, PACKET)
assert read(0x800107B0 + (0x7C >> 2), 1) == b'\x12'
assert read(0x800107B0 + (0x78 >> 2), 1) == b'\0'
enqueue.clear()

for frame in ('000000e81200004c0020820215e00a0610000a063bc00046',
              '000000e80800004c0023000202d0',
              '000000e80400004c002a'):
    raw = bytes.fromhex(frame)
    cpu.mem_write(PACKET, raw)
    assert call(0x514BCE38, PACKET) == 0
    task, forwarded = enqueue.pop()
    expected = bytearray(raw)
    expected[0:2] = bytes.fromhex('127c')
    expected[6] = 1
    assert task == read(0x516E7640, 1)[0]
    assert forwarded == expected, (task, forwarded.hex(), expected.hex())
    print(f'PCM NOS -> MDI send task {task:02x} {forwarded.hex()}')
assert not enqueue

# The original media ingress, off-device checks and local object dispatch
# accept the candidate DSP header and enqueue it for the stock NOS driver.
for opcode in (0x21, 0x24, 0x26, 0x28, 0x2B):
    reply = bytes.fromhex('12007ce808004c0100') + bytes([opcode]) + bytes(4)
    cpu.mem_write(POOL, reply)
    assert call(0x514BCF5C, POOL) == 0
    assert enqueue.pop() == (0x2C, reply)
assert not enqueue
assert read(ROM_BASE, len(body)) == body
print('PASS original NOS E8 route to internal MDI and DSP reply ingress to task 2c; ROM unchanged')
