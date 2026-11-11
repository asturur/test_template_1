#!/usr/bin/env python3
"""Extract exact private NEM-4 instructions; no instruction substitutions."""
import argparse
import hashlib
import json
from pathlib import Path


def write_hex(path, data):
    assert len(data) % 4 == 0
    path.write_text("".join(f"{int.from_bytes(data[i:i+4], 'little'):08x}\n"
                           for i in range(0, len(data), 4)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rom", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    rom = args.rom.read_bytes()
    digest = hashlib.sha256(rom).hexdigest()
    if digest != "26ca1dd937e299fd4ec3ad65a25d395743ae2149311c3d753cbeb5437673dbc5":
        raise ValueError("Unexpected NEM-4 ROM fixture")
    program = (args.output / "program.bin").read_bytes()
    assert len(program) <= 8192
    write_hex(args.output / "program.hex", program.ljust(8192, b"\0"))
    write_hex(args.output / "app.hex", rom[0x320000:0x3d0000])
    (args.output / "inputs.json").write_text(json.dumps({
        "rom_sha256": digest, "original_instruction_range": ["50320000", "503d0000"],
        "instruction_window_sha256": hashlib.sha256(rom[0x320000:0x3d0000]).hexdigest(),
        "executed_original_entries": ["5032ca14", "50321860", "503212c0",
                                      "50330c7c", "50330d10", "50321868",
                                      "50331c08", "50328460"],
        "instruction_substitutions": [],
        "fixture_only": ["virtual 5812xxxx to physical 0c12xxxx register mapping",
                         "synthetic ISR wrapper/channel/vtable objects in kernel RAM",
                         "synthetic IRQ limit/table with captured disable at 5812010c",
                         "synthetic section page-table entry for original VA lookup",
                         "fixture callback counts and verifies original ISR completion",
                         "bounded SDRAM and kernel scratch RAM"],
    }, indent=2) + "\n")


if __name__ == "__main__":
    main()
