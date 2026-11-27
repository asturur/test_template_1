"""Execute the patched entry instructions and check the original continuation ABI."""
import ast
from pathlib import Path
import struct

from build_virtual_sim import decode16, rules
from unicorn import Uc, UC_ARCH_ARM, UC_MODE_ARM, UC_HOOK_MEM_WRITE
from unicorn.arm_const import (
    UC_ARM_REG_CPSR, UC_ARM_REG_LR, UC_ARM_REG_PC, UC_ARM_REG_R0, UC_ARM_REG_R1,
    UC_ARM_REG_R5, UC_ARM_REG_R12, UC_ARM_REG_SP,
)

here = Path(__file__).resolve().parent
root = here.parents[2]
output_dir = root / "build/mister/reset-observer"
tree = ast.parse((output_dir / "observer.py").read_text())
records = {offset: new for offset, _, new in ast.literal_eval(next(
    node.value for node in tree.body if isinstance(node, ast.Assign)
    and isinstance(node.targets[0], ast.Name) and node.targets[0].id == "records"))}
payload = (output_dir / "trace.bin").read_bytes()
rule = rules()
cases = 0
for target, hook, kind in ((0x51716a00, 0x514c1144, "N"), (0x50316a00, 0x50324dc4, "P")):
    for flags in (0, 0xa0000000, 0xf0000000):
        for value in (4, 7, 0xc, 0x13, 0x17, 0x18, 0xfedcba98):
            uc = Uc(UC_ARCH_ARM, UC_MODE_ARM)
            for page in {target & ~0xfff, hook & ~0xfff, 0x59000000, 0x58004000, 0x80002000}:
                uc.mem_map(page, 0x1000)
            uc.mem_write(target, payload)
            if kind == "N":
                cipher = records[0xc1144]
                branch = struct.pack("<2H", decode16(cipher & 0xffff, 0xc1144, rule),
                                     decode16(cipher >> 16, 0xc1146, rule))
            else:
                branch = struct.pack("<I", records[0x324dc4])
            uc.mem_write(hook, branch)
            uc.reg_write(UC_ARM_REG_CPSR, flags | (0xfb if kind == "N" else 0xd3))
            uc.reg_write(UC_ARM_REG_SP, 0x80002f00)
            regs = range(UC_ARM_REG_R1, UC_ARM_REG_R12 + 1)
            for index, reg in enumerate(regs):
                uc.reg_write(reg, 0x135789ab - index * 0x14245)
            uc.reg_write(UC_ARM_REG_R5, value)
            uc.reg_write(UC_ARM_REG_R0, 0x5800428e if kind == "N" else value)
            caller = 0x514c6717 if kind == "N" else 0x5033c7dc
            uc.reg_write(UC_ARM_REG_LR, 0x514c1143 if kind == "N" else caller)
            uc.mem_write(0x80002f08, struct.pack("<I", caller))
            before = {reg: uc.reg_read(reg) for reg in (*regs, UC_ARM_REG_SP, UC_ARM_REG_CPSR)}
            output = []

            def written(cpu, access, addr, size, data, user_data):
                if addr == 0x59000000:
                    output.append(data)

            uc.hook_add(UC_HOOK_MEM_WRITE, written)
            uc.emu_start(hook | (kind == "N"), hook + 4, count=300)
            assert uc.reg_read(UC_ARM_REG_PC) == hook + 4
            assert uc.reg_read(UC_ARM_REG_R0) == (0x516cecf4 if kind == "N" else 0x20)
            assert all(uc.reg_read(reg) == val for reg, val in before.items())
            assert bytes(output) == f"@{kind}:{value:08x}:{caller:08x}\n".encode()
            if kind == "N":
                assert uc.mem_read(0x5800428e, 1)[0] == value & 0xff
            cases += 1
print(f"PASS {cases} patched instruction, register, flag, stack and trace cases")

cases = 0
for hook, kind, stock, caller in (
    (0x514c2154, "S", bytes.fromhex("00200870"), 0x514c6599),
    (0x5159a5f0, "T", bytes.fromhex("020e0906"), 0x5159a743),
    (0x514a6424, "R", bytes.fromhex("0fe0a0e11cff2fe1"), 0x514c2163),
    (0x514a6424, "R", bytes.fromhex("0fe0a0e11cff2fe1"), 0x514c58e3),
):
    for flags in (0, 0xa0000000, 0xf0000000):
        states = []
        for patched in (False, True):
            uc = Uc(UC_ARCH_ARM, UC_MODE_ARM)
            callback = 0x5034e000
            for page in {0x51716000, hook & ~0xfff, 0x59000000, 0x58004000,
                         callback, 0x80002000}:
                uc.mem_map(page, 0x1000)
            uc.mem_write(0x51716a00, payload)
            if patched:
                offset = hook - 0x51400000
                cipher = records[offset]
                branch = struct.pack("<2H", decode16(cipher & 0xffff, offset, rule),
                                     decode16(cipher >> 16, offset + 2, rule))
                uc.mem_write(hook, branch + stock[4:])
            else:
                uc.mem_write(hook, stock)
            uc.mem_write(callback, bytes.fromhex("1eff2fe1"))
            uc.reg_write(UC_ARM_REG_CPSR, flags | (0xdb if kind == "R" else 0xfb))
            uc.reg_write(UC_ARM_REG_SP, 0x80002f00)
            regs = range(UC_ARM_REG_R0, UC_ARM_REG_R12 + 1)
            for index, reg in enumerate(regs):
                uc.reg_write(reg, 0x135789ab - index * 0x14245)
            uc.reg_write(UC_ARM_REG_R0, 0x06000000)
            uc.reg_write(UC_ARM_REG_R1, 0x58004202 if kind == "S" else 0x13)
            uc.reg_write(UC_ARM_REG_R12, callback)
            uc.reg_write(UC_ARM_REG_LR, caller)
            uc.mem_write(0x80002f00, struct.pack("<II", caller, caller))
            output = []
            uc.hook_add(UC_HOOK_MEM_WRITE, written)
            resume = hook + (8 if kind == "R" else 4)
            uc.emu_start(hook | (kind != "R"), resume, count=300)
            assert uc.reg_read(UC_ARM_REG_PC) == resume
            state = (*[uc.reg_read(reg) for reg in (*regs, UC_ARM_REG_SP, UC_ARM_REG_CPSR)],
                     bytes(uc.mem_read(0x58004202, 1)))
            states.append(state)
            if patched and (kind != "R" or caller == 0x514c2163):
                value = {"S": state[4], "T": 0x0613, "R": callback}[kind]
                assert bytes(output) == f"@{kind}:{value:08x}:{caller:08x}\n".encode()
            else:
                assert not output
        assert states[0] == states[1], (kind, flags, states)
        cases += 1
print(f"PASS {cases} shutdown, MTC state and RTC callback continuation cases")
