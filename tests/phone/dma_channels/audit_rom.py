#!/usr/bin/env python3
"""Check the private NEM-4 DMA register evidence; no firmware is emitted."""
import argparse
import hashlib
import json
import struct

from capstone import CS_ARCH_ARM, CS_MODE_ARM, Cs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rom")
    args = parser.parse_args()
    with open(args.rom, "rb") as source:
        rom = source.read()
    digest = hashlib.sha256(rom).hexdigest()
    assert digest == "26ca1dd937e299fd4ec3ad65a25d395743ae2149311c3d753cbeb5437673dbc5"
    disassembler = Cs(CS_ARCH_ARM, CS_MODE_ARM)

    def instructions(address, count):
        data = rom[address - 0x50000000:address - 0x50000000 + count * 4]
        return [(op.mnemonic, op.op_str) for op in disassembler.disasm(data, address)]

    def words(address, count):
        return list(struct.unpack_from(f"<{count}I", rom, address - 0x50000000))

    helpers = {
        0x50324b8c: 0x304, 0x50324c3c: 0x314, 0x50324c5c: 0x318,
        0x50324c7c: 0x31c, 0x50324c90: 0x320, 0x50324cb0: 0x324,
        0x50324cd0: 0x328, 0x50324ce4: 0x32c,
    }
    for address, offset in helpers.items():
        assert instructions(address, 5) == [
            ("add", "r3, r0, #0x120000"), ("add", f"r3, r3, #0x{offset:x}"),
            ("mov", "r0, r1"), ("mov", "r1, r3"), ("b", "#0x503245bc"),
        ]
    assert instructions(0x503245b0, 6) == [
        ("mov", "r2, #0x58000000"), ("ldr", "r0, [r2, r0]"), ("mov", "pc, lr"),
        ("mov", "r2, #0x58000000"), ("str", "r0, [r2, r1]"), ("mov", "pc, lr"),
    ]
    assert instructions(0x50324bbc, 3) == [
        ("add", "r1, r5, #0x120000"), ("add", "r1, r1, #0x308"),
        ("bl", "#0x503245bc"),
    ]
    assert instructions(0x503212c4, 1) == [("lsl", "r4, r0, #6")]
    assert instructions(0x503212d4, 4) == [
        ("mov", "r0, r4"), ("bl", "#0x50324bf0"),
        ("cmp", "r0, #0"), ("bne", "#0x503212d4"),
    ]
    # Both paced paths shift by a peripheral table entry before subtracting 1.
    assert instructions(0x503215c4, 4) == [
        ("asr", "r1, r7, r1"), ("mov", "r0, r4"),
        ("sub", "r1, r1, #1"), ("bl", "#0x50324ce4"),
    ]
    assert instructions(0x50321424, 4) == [
        ("asr", "r1, r7, #1"), ("mov", "r0, r4"),
        ("sub", "r1, r1, #1"), ("bl", "#0x50324ce4"),
    ]
    assert instructions(0x50321860, 2) == [("mov", "r0, #3"), ("mov", "pc, lr")]
    assert words(0x503460f4, 2) == [0x10121208, 0x10120624]
    assert words(0x50346108, 6) == [15, 15, 1, 15, 7, 2]
    assert words(0x5034614c, 6) == [0, 0, 32, 32, 32, 8]
    assert words(0x50346170, 6) == [0, 0, 2, 2, 2, 0]
    for channel in range(8):
        assert words(0x50347a84 + (0x63 + channel) * 4, 1) == [0x80000820 - channel * 8]
        name = f"IrqDmaChannel{channel}".encode() + b"\0"
        offset = 0x3467bc + channel * 16
        assert rom[offset:offset + len(name)] == name
    print(json.dumps({
        "fixture_sha256": digest,
        "kind": "static original-instruction audit; not an executed driver test",
        "register_helpers": {f"0x{a:08x}": f"channel + 0x{o - 0x300:02x}"
                             for a, o in helpers.items()},
        "control_helper": "0x50324bac, channel + 0x08",
        "stop_and_poll": "0x503212c0..0x50321308",
        "memory_setup": "0x5032130c..0x503213c0: on-chip mode 2/width 16; other mode 4/width 32",
        "memory_count": "0x50321424: (argument >> 1) - 1 even after configuring width 32",
        "paced_count": "0x503215bc..0x503215d0: (argument >> peripheral shift) - 1",
        "completion_status": "0x50321860 returns constant 3; errors must not synthesize a success IRQ",
        "peripheral_targets": {"lcd": "0x10121208", "mmc": "0x10120624"},
        "request_lines": {"lcd_type4": 7, "mmc_type5": 2},
        "peripheral_width_bits": words(0x5034614c, 6),
        "peripheral_count_shift": words(0x50346170, 6),
        "dma_irq": {"channels": "0..7", "bank0_bits": "6..13",
                    "handler_ids": "0x63..0x6a", "name_index_table": "0x50347a84"},
        "open": [
            "See the original setup/start/stop execution fixture; full ISR and other caller paths remain open",
            "Original ISR execution and ACK timing beyond retained LCD source 7",
            "MMC address admission waits for an implemented host/FIFO",
            "Physical UPP controller timing and hardware error status are unverified",
        ],
    }, indent=2))


if __name__ == "__main__":
    main()
