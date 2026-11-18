"""Run the patched NEM-4 send callback, router and deferred work ring on ARM."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from unicorn import Uc, UC_ARCH_ARM, UC_MODE_ARM, UC_HOOK_CODE
from unicorn import UC_HOOK_MEM_READ, UC_HOOK_MEM_WRITE
from unicorn.arm_const import (UC_ARM_REG_CPSR, UC_ARM_REG_LR, UC_ARM_REG_PC,
                               UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_R2,
                               UC_ARM_REG_R3, UC_ARM_REG_SP)

SENTINEL = 0x60000000
RAM = 0x80000000
STACK = 0x801f0000
INPUT = 0x80110000
CHANNEL = 0x80110100
MMIO = 0x581f0000
UNIT = 20
OBJECT = 0x4c
IRQ_ID = 98
IRQ_REGISTRY = 0x80113000
FIQ_ENABLE = 0x581201c8
IRQ_DISABLE = 0x5812010c
TIMER5_STATUS = 0x58120aa8
REGS = (UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_R2, UC_ARM_REG_R3)


class Fixture:
    def __init__(self, patch, window):
        info = json.loads((patch / 'patch.json').read_text())
        image = (patch / 'backing.bin').read_bytes()
        assert hashlib.sha256(image).hexdigest() == info['patched_sha256']
        decoded = window.read_bytes()
        assert hashlib.sha256(decoded).hexdigest() == (
            '01a78abfcbc9ff78ff0e5fb46345ba3f51519a7ebfd6949e3e96ae5f894531dc')
        nos = bytearray(image[:0x400000])
        nos[0xa000:0x2b3000] = decoded

        self.cpu = Uc(UC_ARCH_ARM, UC_MODE_ARM)
        self.map(0x50320000, 0x100000, image[0x320000:0x420000])
        self.map(0x511b6000, 4096, image[0x11b6000:0x11b7000])
        self.map(0x51400000, 0x400000, bytes(nos))
        self.map(RAM, 0x200000)
        self.map(SENTINEL, 4096)
        self.map(MMIO, 4096)
        self.map(0x58120000, 4096)
        self.prepare_interrupts()
        self.write32(0x8000c724 + UNIT * 4, CHANNEL)
        self.cpu.mem_write(0x800c828c, bytes([0x60]))
        self.write32(0x80006bb8, 0x80006bb8)
        self.write32(0x80006bbc, 0x80006bb8)
        self.registers = [0x41554431] + [0] * 12
        self.allocations = 0
        self.interrupt = 0
        self.packets = []
        self.forwarded = []
        self.queued = 0
        self.timer_acknowledgements = 0
        self.stubs = {
            0x516c74fc: lambda: 0,              # Stack frame is outside NOS pool.
            0x516c750c: self.allocate,          # Use distinct guarded fixture blocks.
            0x516c751c: self.deliver_to_task,
            0x50331bf8: self.observe_interrupt_enable,
            0x514a1880: self.wake,
            0x516c7bfc: lambda: 0,              # Stock DOS event publication boundary.
            0x516c7bf0: lambda: 0,              # Stock DOS event acknowledgment.
            0x514a5eac: lambda: 0x12,           # DOS task identity for work-ring drain.
            0x514bce38: self.original_router,
        }
        self.cpu.hook_add(UC_HOOK_CODE, self.code)
        self.cpu.hook_add(UC_HOOK_MEM_READ, self.mmio_read, begin=MMIO, end=MMIO+51)
        self.cpu.hook_add(UC_HOOK_MEM_WRITE, self.mmio_write, begin=MMIO, end=MMIO+51)
        self.cpu.hook_add(UC_HOOK_MEM_WRITE, self.timer_ack,
                          begin=TIMER5_STATUS, end=TIMER5_STATUS)

    def prepare_interrupts(self):
        # Runtime tables normally created by the kernel boot code. Seed the
        # ROM name and an empty registry, then run the real Bind and Enable.
        self.write32(0x800066e4, 0xba)
        self.write32(0x800066e0, IRQ_REGISTRY)
        self.write32(0x80114000, 0x10000000)
        timer5_name = 0x503467b0
        assert self.cpu.mem_read(timer5_name, 9) == b'IrqTimer5'
        self.write32(0x80000828, 0x10000009)
        self.write32(0x8000082c, timer5_name)
        for i in range(IRQ_ID + 1):
            self.write32(0x80000020 + i*4, 0x80000828 if i == IRQ_ID else 0x80114000)

    def map(self, address, size, contents=b''):
        self.cpu.mem_map(address, size)
        if contents:
            self.cpu.mem_write(address, contents)

    def write32(self, address, value):
        self.cpu.mem_write(address, struct.pack('<I', value))

    def read32(self, address):
        return struct.unpack('<I', self.cpu.mem_read(address, 4))[0]

    def reg(self, index):
        return self.cpu.reg_read(REGS[index])

    def code(self, cpu, address, size, data):
        handler = self.stubs.get(address)
        if handler:
            result = handler()
            if result is not None:
                cpu.reg_write(UC_ARM_REG_R0, result)
                cpu.reg_write(UC_ARM_REG_PC, cpu.reg_read(UC_ARM_REG_LR))

    def mmio_read(self, cpu, access, address, size, value, data):
        assert size == 4
        self.write32(address, self.registers[(address-MMIO) // 4])

    def mmio_write(self, cpu, access, address, size, value, data):
        assert size == 4
        i = (address-MMIO) // 4
        if i == 8:
            self.registers[8] &= ~(value & 3)
            return
        if i == 1 and value == 0:
            self.registers[8] = 0
        if i in (6, 7):
            ready = 1 << (i - 2)
            self.registers[8] &= ~ready
            if value:
                self.registers[8] |= ready
        self.registers[i] = value

    def timer_ack(self, cpu, access, address, size, value, data):
        assert size == 4 and value == self.read32(TIMER5_STATUS)
        self.timer_acknowledgements += 1

    def call(self, address, *args, return_to=SENTINEL):
        self.cpu.reg_write(UC_ARM_REG_CPSR, 0x13)
        self.cpu.reg_write(UC_ARM_REG_SP, STACK)
        self.cpu.reg_write(UC_ARM_REG_LR, return_to)
        for i, reg in enumerate(REGS):
            self.cpu.reg_write(reg, args[i] if i < len(args) else 0)
        self.cpu.emu_start(address, return_to, count=100_000)
        assert self.cpu.reg_read(UC_ARM_REG_PC) == return_to, 'native call did not return'
        return self.reg(0)

    def allocate(self):
        assert 0 < self.reg(0) <= 256
        self.allocations += 1
        return 0x80120000 + self.allocations * 256

    def observe_interrupt_enable(self):
        irq = self.reg(0)
        assert self.interrupt in (0, irq) and self.read32(irq) == IRQ_ID
        assert self.read32(IRQ_REGISTRY + IRQ_ID*4) == irq
        self.interrupt = irq

    def original_router(self):
        address = self.reg(0)
        if address == INPUT:
            self.forwarded.append(bytes(self.cpu.mem_read(address, 10)))
            return 7
        return None                     # Execute the original route for every reply.

    def deliver_to_task(self):
        task = self.reg(0)
        frame = bytes(self.cpu.mem_read(self.reg(1), 14))
        assert task == 0x2c
        assert frame[:8] == bytes([0, 0x60, 0x7c, 0xe8, 8, 0, OBJECT, 1])
        self.packets.append(frame[8:12])
        return 1

    def wake(self):
        self.queued += 1
        return 0

    def send(self, id, transaction, payload=b'', *, resource=0xe8, unit=UNIT):
        frame = bytes([0, 0x60, 0, resource, len(payload)+4, 0, 0, OBJECT,
                       transaction, id]) + payload
        self.cpu.mem_write(INPUT, frame)
        self.call(0x514a1794, 4, INPUT, unit, 0)

    def expect(self, *packets):
        assert self.packets == list(map(bytes, packets)), self.packets
        self.packets.clear()

    def complete(self, halves, *, deliver=True):
        self.registers[8] &= ~(halves << 4)
        self.registers[8] |= halves
        self.call(0x5032e6ec, IRQ_ID)
        assert self.registers[8] & 3 == 0
        if deliver:
            self.drain()

    def drain(self):
        dfc = self.interrupt + 20
        assert self.read32(0x80006bb8) == dfc
        # Emulate IRQ return's removal of the queued TDfc. Its Add above was stock.
        self.write32(0x80006bb8, 0x80006bb8)
        self.write32(0x80006bbc, 0x80006bb8)
        self.write32(dfc, 0)
        self.call(self.read32(dfc+8), self.read32(dfc+12))
        self.call(0x514a2608)           # Run the original DOS work-ring dispatcher.


def verify(f):
    start = bytes.fromhex('820215e00a0610000a063bc00046')
    filled = bytes.fromhex('000202d0')
    last = bytes.fromhex('00010020')
    f.send(0x14, 1, resource=0x0b)
    assert len(f.forwarded) == 1 and f.allocations == 0
    f.cpu.mem_write(INPUT, bytes([0, 0x60, 0, 0xe8, 18, 0, 0, OBJECT, 10, 0x20]) + start)
    assert f.call(0x516c7ab8, INPUT, 0, UNIT, return_to=0x5149dae0) == 7
    assert len(f.forwarded) == 2 and f.interrupt == 0  # Other stock caller stays untouched.

    f.send(0x20, 10, start, unit=UNIT+1)
    assert len(f.forwarded) == 3 and not f.interrupt
    f.send(0x2a, 9)
    f.expect([9, 0x2b, 0, 0])
    assert f.allocations == 1 and not f.interrupt
    f.write32(FIQ_ENABLE, 1 << 5)
    f.send(0x20, 10, start)
    assert len(f.forwarded) == 4 and not f.interrupt
    f.write32(FIQ_ENABLE, 0)
    f.send(0x20, 10, start)
    f.expect([10, 0x21, 0, 0])
    assert f.registers[3:6] == [16000, 0x0a061000, 0x0a063bc0]
    assert f.read32(0x58120108) == 1 << 5
    f.write32(TIMER5_STATUS, 1)
    f.call(0x5032e6ec, IRQ_ID)
    assert f.timer_acknowledgements == 1 and f.read32(TIMER5_STATUS) == 1
    assert f.read32(0x80006bb8) == 0x80006bb8   # Timer only: no PCM DFC queued.
    f.write32(0x8000c724 + (UNIT+1) * 4, CHANNEL+0x100)
    f.send(0x20, 99, start, unit=UNIT+1)
    f.expect()
    assert len(f.forwarded) == 5         # Another client cannot steal this stream.
    f.send(0x23, 11, filled)
    f.expect([11, 0x24, 0, 0], [0, 0x26, 0, 1])
    f.send(0x27, 12, filled)
    f.expect([12, 0x28, 0, 0])
    f.complete(1)
    f.expect([0, 0x26, 0, 0])
    f.send(0x27, 13, filled)
    f.expect([13, 0x28, 0, 0])
    f.complete(2, deliver=False)
    f.registers[9] = 0x105
    f.send(0x2a, 14)
    f.expect([14, 0x2b, 2, 10])
    assert f.registers[1] == 0
    f.drain()
    f.expect()                         # A pending completion cannot cross the stop.

    f.send(0x20, 15, start)
    f.expect([15, 0x21, 0, 0])
    f.send(0x23, 16, last)
    f.expect([16, 0x24, 0, 0])
    f.complete(1)
    f.expect([0, 0x2b, 0, 64])
    assert f.registers[1] == 0 and f.queued == 3
    f.send(0x20, 17, start)
    f.expect([17, 0x21, 0, 0])
    f.send(0x23, 18, filled)
    f.expect([18, 0x24, 0, 0], [0, 0x26, 0, 1])
    f.write32(0x8000c724 + UNIT * 4, 0)
    f.complete(1)
    f.expect()                         # Closed channel receives no new request.
    assert f.registers[1] == 0
    f.write32(0x8000c724 + UNIT * 4, CHANNEL)
    f.send(0x20, 19, start)
    f.expect([19, 0x21, 0, 0])
    f.send(0x23, 20, filled)
    f.expect([20, 0x24, 0, 0], [0, 0x26, 0, 1])
    f.send(0x27, 21, filled)
    f.expect([21, 0x28, 0, 0])
    f.complete(3)
    f.expect([0, 0x26, 0, 0])
    f.send(0x27, 22, filled)
    f.expect([22, 0x28, 0, 0], [0, 0x26, 0, 1])
    f.send(0x27, 23, filled)
    f.expect([23, 0x28, 0, 0])
    acknowledgements = f.timer_acknowledgements
    f.write32(FIQ_ENABLE, 1 << 5)
    f.call(0x5032e6ec, IRQ_ID)
    assert f.read32(IRQ_DISABLE) == 1 << 5 and f.timer_acknowledgements == acknowledgements
    f.write32(FIQ_ENABLE, 0)
    f.write32(0x58120108, 0)
    f.send(0x20, 24, start)
    f.expect([24, 0x21, 0, 0])
    assert f.read32(0x58120108) == 1 << 5
    print('PASS native send closure, original NOS reply routing, IRQ/DFC and work ring,'
          ' STOP/restart, coalesced completions and shared timer/FIQ')


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('patch', type=Path)
    p.add_argument('window', type=Path)
    a = p.parse_args()
    verify(Fixture(a.patch, a.window))
