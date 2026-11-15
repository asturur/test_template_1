"""Independent ARM execution plus mathematical/output checks for original bytes."""
import hashlib
from collections import Counter

from unicorn import Uc, UC_ARCH_ARM, UC_HOOK_CODE, UC_MODE_ARM
from unicorn.arm_const import (UC_ARM_REG_CPSR, UC_ARM_REG_LR, UC_ARM_REG_PC,
                               UC_ARM_REG_R0, UC_ARM_REG_SP)

from workloads import PAYLOAD_BASE, RAM_BASE, RAM_SIZE, ROM_BASE


def verify(case, payload, firmware):
    cpu = Uc(UC_ARCH_ARM, UC_MODE_ARM)
    cpu.mem_map(PAYLOAD_BASE, 0x100000)
    cpu.mem_write(PAYLOAD_BASE, bytes(payload))
    cpu.mem_map(ROM_BASE, 0x100000)
    cpu.mem_write(ROM_BASE, firmware)
    cpu.mem_map(RAM_BASE, RAM_SIZE)
    cpu.mem_map(0, 0x10000)
    for address, data in case['writes']:
        cpu.mem_write(address, data)
    cpu.reg_write(UC_ARM_REG_CPSR, 0x13)
    cpu.reg_write(UC_ARM_REG_SP, 0x8001b000)
    for n in range(4, 12):
        cpu.reg_write(UC_ARM_REG_R0+n, 0x12340000+n)
    addresses = Counter()

    def executed(c, address, size, unused):
        if address == 0x1000:
            c.emu_stop()
        else:
            if not (PAYLOAD_BASE <= address < PAYLOAD_BASE+len(payload)
                    or ROM_BASE <= address < ROM_BASE+len(firmware)):
                raise ValueError(f'unexpected oracle execution at {address:08x}')
            addresses[address] += 1

    cpu.hook_add(UC_HOOK_CODE, executed)
    for i in range(case['iterations']):
        for n, value in enumerate(case['regs']):
            cpu.reg_write(UC_ARM_REG_R0+n, value+i*case['strides'][n])
        saved = [cpu.reg_read(UC_ARM_REG_R0+n) for n in range(4, 12)]
        cpu.reg_write(UC_ARM_REG_LR, 0x1000)
        cpu.emu_start(PAYLOAD_BASE+case['entry'], 0, count=2000000)
        if cpu.reg_read(UC_ARM_REG_PC) != 0x1000:
            raise ValueError('original function did not return')
        if cpu.reg_read(UC_ARM_REG_SP) != 0x8001b000:
            raise ValueError('original function unbalanced its stack')
        if [cpu.reg_read(UC_ARM_REG_R0+n) for n in range(4, 12)] != saved:
            raise ValueError('callee-saved register changed')
    outputs = []
    for address, expected in case['checks']:
        got = bytes(cpu.mem_read(address, len(expected)))
        if got != expected:
            raise ValueError(f'{case["id"]} differs from mathematical output at {address:08x}')
        outputs.append(dict(address=hex(address), bytes=len(got),
                            sha256=hashlib.sha256(got).hexdigest()))
    return dict(status='PASS', instructions=sum(addresses.values()),
                payload_instructions=sum(n for a, n in addresses.items() if a < ROM_BASE),
                helper_instructions=sum(n for a, n in addresses.items() if a >= ROM_BASE),
                executed_min=hex(min(addresses)), executed_max=hex(max(addresses)),
                outputs=outputs)
