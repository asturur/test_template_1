#!/usr/bin/env python3
"""Validate assembled kernels/checks using installed Unicorn, not HDL timing.

Start at the kernel with specified registers/memory/CP15 state. This qualifies
the test binaries and their assertions, NOT boot, MMU, cache, RTL or performance.
No dependency download is performed.
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

from run import ROOT, digest, locations, write_json


def execute(case, binary, kernel, corrupt=False):
    from unicorn import Uc, UC_ARCH_ARM, UC_MODE_ARM, UC_HOOK_CODE, UC_HOOK_MEM_WRITE
    from unicorn.arm_const import UC_ARM_REG_R0, UC_ARM_REG_SP, UC_ARM_REG_LR, UC_ARM_REG_PC, UC_ARM_REG_CPSR

    uc = Uc(UC_ARCH_ARM, UC_MODE_ARM)
    uc.mem_map(0, 0x10000)
    uc.mem_write(0, binary)
    uc.mem_map(0x80000000, 0x20000)
    uc.mem_map(0xF0000000, 0x1000)
    uc.mem_map(0x100000, 0x1000)
    for n in range(256):
        uc.mem_write(0x80001000+n*4, (0x100+n).to_bytes(4, "little"))
        uc.mem_write(0x80002000+n*4, (0x1000+n).to_bytes(4, "little"))
    uc.mem_write(0x80001020, (0x80FF7F01).to_bytes(4, "little"))
    for n in range(65):
        uc.mem_write(0x80010000+n*256, (0x200+n).to_bytes(4, "little"))
    uc.reg_write(UC_ARM_REG_CPSR, 0x13)
    # This sets only kernel preconditions; it is not a phone MMU model.
    uc.cpr_write(15, 0, 2, 0, 0, 0, False, 0x0A004000)
    uc.cpr_write(15, 0, 3, 0, 0, 0, False, 1)
    values = {0: 0, 1: 3, 2: 5, 3: 7, 4: 0x80001000,
              5: 0x80002000, 6: 0x80003000, 7: 1, 8: 0, 9: 0, 10: 5}
    values.update({int(k): v for k, v in case.get("initial_registers", {}).items()})
    for register, value in values.items():
        uc.reg_write(UC_ARM_REG_R0+register, value)
    uc.reg_write(UC_ARM_REG_SP, 0x8001F000)
    uc.reg_write(UC_ARM_REG_LR, 0x100000)
    count = [0]
    def instruction(_uc, address, size, data):
        count[0] += 1
    hook = uc.hook_add(UC_HOOK_CODE, instruction)
    uc.emu_start(kernel, case["body_end"], count=100000)
    uc.hook_del(hook)
    if uc.reg_read(UC_ARM_REG_PC) != case["body_end"]:
        raise ValueError("kernel failed to reach end marker")
    # kernel's MOV r9,lr is outside the measured window.
    body_instructions = count[0]-1
    for register, expected in case["expected"].items():
        actual = uc.reg_read(UC_ARM_REG_R0+int(register))
        if actual != expected:
            raise ValueError(f"r{register}: {actual:08x}, expected {expected:08x}")
    if "flags" in case and uc.reg_read(UC_ARM_REG_CPSR)&0xF0000000 != case["flags"]:
        raise ValueError("NZCV oracle differs from assembled program")
    if corrupt:
        uc.reg_write(UC_ARM_REG_R0, uc.reg_read(UC_ARM_REG_R0)^1)
    terminal = []
    def write(_uc, access, address, size, value, data):
        if address == 0xF0000000:
            terminal.append(value)
            _uc.emu_stop()
    uc.hook_add(UC_HOOK_MEM_WRITE, write)
    uc.emu_start(case["body_end"], 0x100000, count=100000)
    if corrupt:
        if terminal != [0x4641494C]:
            raise ValueError("corrupted output did not trigger guest failure assertion")
    elif terminal or uc.reg_read(UC_ARM_REG_PC) != 0x100000:
        raise ValueError(f"guest postcondition failed: terminal={terminal}")
    return body_instructions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("name", nargs="?")
    parser.add_argument("--native-probe", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.native_probe:
        from unicorn import Uc, UC_ARCH_ARM, UC_MODE_ARM
        uc = Uc(UC_ARCH_ARM, UC_MODE_ARM)
        uc.mem_map(0, 4096)
        return 0
    if args.name is None:
        parser.error("experiment name required")
    _, output = locations(args.name)
    manifest = json.loads((output/"manifest.json").read_text())
    result = dict(scope="software validation of kernels and guest checks; no HDL/timing/MMU claim", rows=[])
    try:
        import unicorn
    except ImportError:
        result.update(status="BLOCKED", reason="installed Unicorn unavailable; no download attempted")
        write_json(output/"program-validation.json", result)
        return 2
    result["unicorn_version"] = unicorn.__version__
    # Native initialization can terminate the interpreter (e.g. SIGILL on this
    # host). Probe in a child and record BLOCKED rather than losing the report.
    probe = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--native-probe"],
                           capture_output=True, text=True)
    if probe.returncode:
        result.update(status="BLOCKED", reason="native Unicorn initialization failed",
                      native_exit_code=probe.returncode, diagnostic=probe.stderr[-2000:])
        write_json(output/"program-validation.json", result)
        print(f"BLOCKED: native Unicorn initialization; exit={probe.returncode}")
        return 2
    for case in manifest["benchmarks"]:
        directory = (ROOT/case["hex"]).parent
        binary = (directory/"program.bin").read_bytes()
        if digest(binary) != case["binary_sha256"]:
            raise ValueError("binary changed after preparation")
        nm = subprocess.check_output(["arm-none-eabi-nm", str(directory/"program.elf")], text=True)
        kernel = next(int(line.split()[0],16) for line in nm.splitlines() if line.split()[-1:] == ["kernel"])
        try:
            count = execute(case, binary, kernel)
            execute(case, binary, kernel, corrupt=True)
            row = dict(case=case["id"], status="PASS", body_isa_instructions=count,
                       binary_sha256=case["binary_sha256"], guest_assertion_negative_control="PASS")
        except Exception as exc:
            row = dict(case=case["id"], status="FAIL", reason=str(exc))
        result["rows"].append(row)
        print(row, flush=True)
    result["status"] = "PASS" if all(r["status"] == "PASS" for r in result["rows"]) else "FAIL"
    write_json(output/"program-validation.json", result)
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
