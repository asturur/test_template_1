#!/usr/bin/env python3
"""Record the inspected NEM-4 startup tables, MMIO aliases, and disassembly."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = "afc1cc8b693f2b68d23ca203aa4d4eb4266baad4ab718f013a33b915d39574ef"


def inspect(rom):
    from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM
    payload = rom.read_bytes()
    sha = hashlib.sha256(payload).hexdigest()
    if sha != EXPECTED:
        raise ValueError("fixed startup offsets apply only to the inspected N-Gage 4.03 SYM.ROM")
    def word(at):
        return struct.unpack_from("<I", payload, at)[0]
    tables = []
    for at in (0x638, 0x744, 0x830):
        entries = []
        rom_offset = 0
        for i in range(word(at)):
            address, size, flags, extra = struct.unpack_from("<4I", payload, at + 8 + 16 * i)
            entry = dict(address=address, size=size, flags=flags, extra=extra, type=flags & 31)
            if entry["type"] == 1:
                entry["hypothesized_file_offset"] = rom_offset
                rom_offset += size
            entries.append(entry)
        tables.append(dict(offset=at, count=word(at), selector=word(at + 4), entries=entries))
    aliases = []
    for physical, virtual in ((0x61b8, 0x6194), (0x61e0, 0x61bc), (0x61fc, 0x61e4)):
        physical_address, virtual_address = word(physical), word(virtual)
        if virtual_address - physical_address != 0x4c000000:
            raise ValueError("MMIO literal pair does not match the inspected M-bit-dependent selection")
        aliases.append(dict(physical_literal=physical, virtual_literal=virtual,
                            physical_address=physical_address, virtual_address=virtual_address))
    decoder = Cs(CS_ARCH_ARM, CS_MODE_ARM)
    decoder.skipdata = True
    code = {}
    for name, start, end in (("flash_probe", 0x95c, 0xb6c),
                             ("rom_map_and_next_image_caller", 0xdc4, 0xef8),
                             ("rom_map_and_next_image_scan", 0x1c54, 0x1ff8),
                             ("bsi_adc_conversion", 0x3138, 0x31a8),
                             ("bsi_high_input_stop", 0x2f60, 0x2f7c),
                             ("bsi_caller_and_shadow_init", 0x352c, 0x360c),
                             ("timer_bootstrap_and_wait", 0x3200, 0x3298),
                             ("cbus_register_lookup", 0x34f0, 0x3528),
                             ("cbus_transport", 0x3650, 0x36dc),
                             ("clock_startup", 0x36dc, 0x39c0),
                             ("mmio_selection", 0x617c, 0x6200),
                             ("lcd_init_dispatch", 0x6200, 0x63f8),
                             ("lcd_clear_and_transport", 0x6448, 0x66b8),
                             ("lcd_commands_and_packing", 0x66e4, 0x6d80),
                             ("atomic_set_and_mmu_query", 0x66b8, 0x66e4)):
        code[name] = [dict(address=i.address, bytes=i.bytes.hex(), mnemonic=i.mnemonic, operands=i.op_str)
                      for i in decoder.disasm(payload[start:end], start)]
    return dict(firmware=str(rom), sha256=sha, bytes=len(payload),
                header=dict(rom_base=word(0x8c), rom_size=word(0x90), root_list=word(0x94),
                            kernel_data=word(0x98)),
                tables=tables, rom_mapping_verified=False,
                mmio_alias_selections=aliases, disassembly=code,
                disassembly_note="Ranges include literal pools; decoded words are not all executed instructions.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rom", type=Path, default=ROOT / "firmware" / "SYM.ROM")
    parser.add_argument("--output", type=Path, default=ROOT / "build" / "sim" / "boot-analysis.json")
    args = parser.parse_args()
    report = inspect(args.rom.expanduser().resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Recorded {len(report['tables'])} startup tables and verified literal selections in {args.output}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, ImportError) as error:
        raise SystemExit(str(error))
