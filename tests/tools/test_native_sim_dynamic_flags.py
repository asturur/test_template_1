"""Execute original NEM-4 dynamic-flags service, getter and status mapping.

Allocation, trace/lock and transport leaves are fixture services. Cache contents
are explicit inputs; this does not force SIM-ready in production or prove card
initialization. In particular, absent optional flags must complete as0x24.
"""
from pathlib import Path
import hashlib
import struct
from unicorn import Uc, UC_ARCH_ARM, UC_MODE_ARM, UC_HOOK_CODE
from unicorn.arm_const import *

ROOT = Path(__file__).resolve().parents[2]
image = (ROOT / 'firmware/THC N-Gage ROM Dump/ngage-gsmstuff-0x5149D280.dll').read_bytes()
assert hashlib.sha256(image).hexdigest() == 'e5870e918c90d9c7a6403eb0ee305d174e906aeae0a7fa8069e85a18aeec7aa1'
ROM, BASE = image[96:], 0x5149d280
row = ROM[0x516e0758-BASE:0x516e0764-BASE]
assert row == bytes.fromhex('29372a007533000000a70c80')
assert struct.unpack_from('<II', ROM, 0x516fb8c0-BASE) == (0x3375, 0x51661635)


def verify(valid, flags):
    u = Uc(UC_ARCH_ARM, UC_MODE_ARM)
    u.mem_map(0x51400000, 0x400000)
    u.mem_write(BASE, ROM)
    u.mem_map(0x80000000, 0x120000)
    stop, request, reply = 0x80100000, 0x80100100, 0x80100200
    owner, envelope = 0x800ca700, 0x80100300
    u.mem_write(request, bytes.fromhex('42293700'))
    u.mem_write(reply, b'\xa5'*8)
    u.mem_write(0x800ce04e, bytes([2 if valid else 0]))
    u.mem_write(0x800ce334, flags)
    sent, freed, allocs = [], [], []

    def hook(cpu, address, size, opaque):
        if address == stop:
            cpu.emu_stop()
            return
        args = [cpu.reg_read(r) for r in (UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_R2, UC_ARM_REG_R3)]
        if address == 0x514b9a44:
            assert args[0] == 8
            allocs.append(args[0])
            cpu.reg_write(UC_ARM_REG_R0, reply)
        elif address == 0x516c74f4:
            assert args[2] == 4
            cpu.mem_write(args[0], bytes(cpu.mem_read(args[1], args[2])))
        elif address == 0x5165eb50:
            assert args == [owner, envelope, reply, 8], args
            sent.append(bytes(cpu.mem_read(reply, 8)))
        elif address == 0x514b9ab4:
            freed.append(args[0])
        elif address in (0x51615ccc, 0x516c757c, 0x516c7584):
            pass  # native optional trace and critical-section leaves
        else:
            return
        cpu.reg_write(UC_ARM_REG_PC, cpu.reg_read(UC_ARM_REG_LR))

    u.hook_add(UC_HOOK_CODE, hook)
    regs = ((UC_ARM_REG_CPSR, 0x13), (UC_ARM_REG_SP, 0x8011f000),
            (UC_ARM_REG_LR, stop|1), (UC_ARM_REG_R0, owner),
            (UC_ARM_REG_R1, 0), (UC_ARM_REG_R2, envelope), (UC_ARM_REG_R3, request))
    for reg, value in regs:
        u.reg_write(reg, value)
    u.emu_start(0x51661635, 0, count=50000)
    assert u.reg_read(UC_ARM_REG_PC) == stop
    assert u.reg_read(UC_ARM_REG_SP) == 0x8011f000
    assert allocs == [8] and freed == [request] and len(sent) == 1
    expected = bytes.fromhex('422a37') + bytes([1 if valid else 0x24])
    assert sent[0][:4] == expected, sent
    assert sent[0][4:] == (flags if valid else b'\xa5'*4), sent
    assert bytes(u.mem_read(BASE, len(ROM))) == ROM
    return sent[0].hex()


for present, payload in ((False, bytes(4)), (True, bytes(4)),
                         (True, bytes.fromhex('01020304'))):
    print('PASS native SIM29/37', 'present' if present else 'absent', verify(present, payload))
