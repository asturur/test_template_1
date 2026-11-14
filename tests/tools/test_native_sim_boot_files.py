"""Original NOS post-ready file phase and its SIM-rejection result.

Immutable original instructions execute at5150F004 and5150B65C. File-provider,
directory and PMM leaves are spies; the fixture supplies a normal directory,
no optional services and a missing-file status. This tests native control flow,
not the complete card driver, RTOS, writable SIM files or hardware readiness.
Pair with tests/phone/card_fixture/mandatory.v for actual RTL APDU contents.
"""
from pathlib import Path
import hashlib
import json

from unicorn import Uc, UC_ARCH_ARM, UC_MODE_ARM, UC_HOOK_CODE
from unicorn.arm_const import (
    UC_ARM_REG_CPSR, UC_ARM_REG_SP, UC_ARM_REG_LR, UC_ARM_REG_PC,
    UC_ARM_REG_R0,
)

ROOT = Path(__file__).resolve().parents[2]
image = (ROOT / 'firmware/THC N-Gage ROM Dump/ngage-gsmstuff-0x5149D280.dll').read_bytes()
assert hashlib.sha256(image).hexdigest() == (
    'e5870e918c90d9c7a6403eb0ee305d174e906aeae0a7fa8069e85a18aeec7aa1')
rom = image[96:]
required = (0x6f74, 0x6f7e, 0x6f20, 0x6f7b)
results = []

for missing in (*required, None):
    cpu = Uc(UC_ARCH_ARM, UC_MODE_ARM)
    cpu.mem_map(0x51400000, 0x400000)
    cpu.mem_write(0x5149d280, rom)
    cpu.mem_map(0x80000000, 0x100000)
    cpu.reg_write(UC_ARM_REG_CPSR, 0x13)
    reads, events, state_changes = [], [], []

    def leaf(c, address, size, unused):
        if address == 0x80000000:
            c.emu_stop()
            return
        if address == 0x5150af0c:
            file_id = c.reg_read(UC_ARM_REG_R0)
            reads.append(file_id)
            c.reg_write(UC_ARM_REG_R0, 0x0b if file_id == missing else 1)
        elif address == 0x5150e774:
            c.reg_write(UC_ARM_REG_R0, 1)  # normal GSM directory
        elif address in (0x515136c4, 0x5151260c, 0x51512828):
            c.reg_write(UC_ARM_REG_R0, 1)  # PMM housekeeping leaves
        elif address == 0x51615174:
            events.append(c.reg_read(UC_ARM_REG_R0))
        elif address == 0x51615694:
            state_changes.append(c.reg_read(UC_ARM_REG_R0))
        else:
            return
        c.reg_write(UC_ARM_REG_PC, c.reg_read(UC_ARM_REG_LR))

    cpu.hook_add(UC_HOOK_CODE, leaf)

    def call(address, arg=0):
        cpu.reg_write(UC_ARM_REG_SP, 0x800ff000)
        cpu.reg_write(UC_ARM_REG_LR, 0x80000000)
        cpu.reg_write(UC_ARM_REG_R0, arg)
        cpu.emu_start(address | 1, 0, count=10000)
        assert cpu.reg_read(UC_ARM_REG_PC) == 0x80000000
        assert cpu.reg_read(UC_ARM_REG_SP) == 0x800ff000
        return cpu.reg_read(UC_ARM_REG_R0)

    result = call(0x5150f004)
    assert result == (0x25f if missing else 0x25e)
    expected = required[:required.index(missing) + 1] if missing else required
    assert reads == list(expected)
    call(0x5150b65c, result)
    assert events == ([0x75] if missing else [])
    assert state_changes == ([0] if missing else [1])
    assert bytes(cpu.mem_read(0x5149d280, len(rom))) == rom
    results.append(dict(missing=missing, reads=reads, result=result,
                        events=events, state_changes=state_changes))

out = ROOT / 'build/sim/unit-native-sim-boot-files'
out.mkdir(parents=True, exist_ok=True)
(out / 'result.json').write_text(json.dumps(results, indent=2) + '\n')
print('PASS 5 original NOS file/startup-dispatch cases: missing mandatory EF -> '
      '025F/070D-reason75; all four ->025E without rejection; ROM unchanged')
