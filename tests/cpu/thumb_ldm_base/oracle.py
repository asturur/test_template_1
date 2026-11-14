#!/usr/bin/env python3
"""Independent Thumb format15 register/writeback oracle using Unicorn."""
from unicorn import Uc, UC_ARCH_ARM, UC_MODE_ARM
from unicorn.arm_const import UC_ARM_REG_R0, UC_ARM_REG_CPSR, UC_ARM_REG_PC
import struct

u = Uc(UC_ARCH_ARM, UC_MODE_ARM)
u.mem_map(0x10000000, 4096)
u.mem_map(0x20000000, 4096)
regs = [UC_ARM_REG_R0 + n for n in range(8)]
count = 0
for load in (0, 1):
    for base in range(8):
        for mask in range(1, 256):
            # ARMv4T STM with a non-lowest base in the list is unpredictable.
            if not load and mask & (1 << base) and mask & ((1 << base) - 1):
                continue
            before = [0x12340000 + n for n in range(8)]
            before[base] = 0x20000000
            values = [0x56780000 + n for n in range(8)]
            u.mem_write(0x20000000, struct.pack('<8I', *values))
            opcode = 0xc000 | (load << 11) | (base << 8) | mask
            u.mem_write(0x10000000, struct.pack('<H', opcode))
            u.ctl_remove_cache(0x10000000, 0x10000004)
            u.reg_write(UC_ARM_REG_CPSR, 0x60000030)
            for r, value in zip(regs, before):
                u.reg_write(r, value)
            u.emu_start(0x10000001, 0x10000002, count=1)
            assert u.reg_read(UC_ARM_REG_PC) == 0x10000002
            assert u.reg_read(UC_ARM_REG_CPSR) == 0x60000030
            selected = [n for n in range(8) if mask & (1 << n)]
            expected = list(before)
            if load:
                for n, reg in enumerate(selected):
                    expected[reg] = values[n]
            else:
                stored = struct.unpack('<%dI' % len(selected),
                                       u.mem_read(0x20000000, len(selected) * 4))
                assert stored == tuple(before[n] for n in selected)
            if not load or not mask & (1 << base):
                expected[base] = 0x20000000 + len(selected) * 4
            assert [u.reg_read(r) for r in regs] == expected, (load, base, mask)
            count += 1
print(f'PASS: {count} independent Thumb LDM/defined-STM register/flags/writeback cases')
