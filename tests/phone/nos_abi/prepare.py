#!/usr/bin/env python3
"""Prepare private NEM-4 instruction fixtures without changing the inputs."""
import argparse
import hashlib
import json
import struct
import subprocess
from pathlib import Path

def read_fixture(path, expected):
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != expected:
        raise ValueError(f"Unexpected NEM-4 fixture {path}")
    return data

def write_hex(path, data):
    assert len(data) % 4 == 0
    path.write_text("".join(f"{int.from_bytes(data[i:i+4], 'little'):08x}\n"
                           for i in range(0, len(data), 4)))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("nos", type=Path)
    parser.add_argument("window", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    app = read_fixture(args.app, "26ca1dd937e299fd4ec3ad65a25d395743ae2149311c3d753cbeb5437673dbc5")
    nos = read_fixture(args.nos, "e5870e918c90d9c7a6403eb0ee305d174e906aeae0a7fa8069e85a18aeec7aa1")
    window = read_fixture(args.window, "01a78abfcbc9ff78ff0e5fb46345ba3f51519a7ebfd6949e3e96ae5f894531dc")
    body = nos[96:]
    assert window[0x9d280 - 0xa000:] == body[:0x2b3000 - 0x9d280]
    mapped = bytearray(0x400000)
    mapped[0xa000:0x2b3000] = window
    mapped[0x9d280:0x9d280+len(body)] = body
    symbols = {}
    for line in subprocess.check_output(["arm-none-eabi-nm", str(args.output / "program.elf")], text=True).splitlines():
        fields = line.split()
        if len(fields) == 3:
            symbols[fields[2]] = int(fields[0], 16)
    stubs = {
        0x516c6f20: ("descriptor_capacity", False),
        0x516c6f14: ("descriptor_write8", False),
        0x516c6f2c: ("descriptor_write16", False),
        0x516c74ec: ("pool_allocate", True),
    }
    replacements = []
    for addr, (symbol, thumb) in stubs.items():
        offset = addr - 0x51400000
        original = bytes(mapped[offset:offset+8])
        prefix = struct.pack("<HH", 0x4b00, 0x4718) if thumb else struct.pack("<I", 0xe51ff004)
        mapped[offset:offset+8] = prefix + struct.pack("<I", symbols[symbol])
        replacements.append({"address": f"0x{addr:08x}", "symbol": symbol,
                             "original_bytes": original.hex(), "fixture_target": symbols[symbol]})
    args.output.mkdir(parents=True, exist_ok=True)
    write_hex(args.output / "app.hex", app[0x320000:0x3d0000])
    write_hex(args.output / "ldd.hex", app[0x11b4000:0x11b5000])
    write_hex(args.output / "nos.hex", mapped)
    program = (args.output / "program.bin").read_bytes()
    assert len(program) <= 8192
    write_hex(args.output / "program.hex", program.ljust(8192, b"\0"))
    (args.output / "inputs.json").write_text(json.dumps({
        str(path): hashlib.sha256(data).hexdigest()
        for path, data in ((args.app, app), (args.nos, nos), (args.window, window))
    }, indent=2) + "\n")
    (args.output / "stub-boundaries.json").write_text(json.dumps(replacements, indent=2) + "\n")

if __name__ == "__main__":
    main()
