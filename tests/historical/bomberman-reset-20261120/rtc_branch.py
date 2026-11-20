"""Run original ecust and NOS shutdown decisions against scoped RTC controls."""
from pathlib import Path
import hashlib

from unicorn import Uc, UC_ARCH_ARM, UC_MODE_ARM, UC_HOOK_CODE
from unicorn.arm_const import UC_ARM_REG_CPSR, UC_ARM_REG_LR, UC_ARM_REG_PC, UC_ARM_REG_R0
from unicorn.arm_const import UC_ARM_REG_R1, UC_ARM_REG_R2, UC_ARM_REG_SP

root = Path(__file__).resolve().parents[3]
core = (root / "build/firmware/nem4-factory/core.bin").read_bytes()
rom = (root / "firmware/THC N-Gage ROM Dump/ngage-gsmstuff-0x5149D280.dll").read_bytes()
assert hashlib.sha256(core).hexdigest() == "be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524"
assert hashlib.sha256(rom).hexdigest() == "e5870e918c90d9c7a6403eb0ee305d174e906aeae0a7fa8069e85a18aeec7aa1"
for status, clock, alarm, expected in (
    (8, 43200, 0, 0x15), (0x18, 43200, 0, 0x15),
    (0, 43200, 0, 0), (0x10, 43200, 0, 0),
    (0, 43200, 43204, 0x15), (0, 43200, 43206, 0),
):
    uc = Uc(UC_ARCH_ARM, UC_MODE_ARM)
    uc.mem_map(0x50000000, 0x1800000)
    uc.mem_write(0x50000000, core)
    uc.mem_write(0x5149d280, rom[96:])
    uc.mem_map(0x58004000, 0x1000)
    uc.mem_map(0x80000000, 0x10000)
    uc.reg_write(UC_ARM_REG_CPSR, 0x13)
    uc.reg_write(UC_ARM_REG_SP, 0x80008000)
    uc.reg_write(UC_ARM_REG_R0, 1)
    times = []
    observed = {}

    def return_value(machine, value):
        machine.reg_write(UC_ARM_REG_R0, value)
        machine.reg_write(UC_ARM_REG_PC, machine.reg_read(UC_ARM_REG_LR))

    def instruction(machine, pc, _size, _opaque):
        if pc == 0x514a6410:
            machine.reg_write(UC_ARM_REG_R0, 0x80000800)
            machine.reg_write(UC_ARM_REG_PC, 0x5034fad8)
        elif pc == 0x5034f5f0:
            assert machine.reg_read(UC_ARM_REG_R1) == 0x15
            assert machine.reg_read(UC_ARM_REG_R2) == 0x10
            observed["register"] = 0x15
            return_value(machine, status)
        elif pc in (0x5034ffcc, 0x5034f374, 0x5034f4c0, 0x503501a0, 0x5152fc7c):
            return_value(machine, 0)
        elif pc == 0x5034fb28:
            times.append(machine.reg_read(UC_ARM_REG_R0))
        elif pc == 0x5034fb44:
            times.append(machine.reg_read(UC_ARM_REG_R0))
        elif pc == 0x503500c0:
            value = clock if machine.reg_read(UC_ARM_REG_R0) == times[0] else alarm
            return_value(machine, value)
        elif pc == 0x515b7db4:
            return_value(machine, 0)
        elif pc in (0x514c1138, 0x514c10b4):
            observed["requested"] = machine.reg_read(UC_ARM_REG_R0) if pc == 0x514c1138 else 0
            machine.emu_stop()

    uc.hook_add(UC_HOOK_CODE, instruction)
    uc.emu_start(0x514c214d, 0, count=400)
    assert observed == {"register": 0x15, "requested": expected}, observed
    print(f"PASS status {status:#04x}, clock {clock}, alarm {alarm}, reset {expected:#04x}")
