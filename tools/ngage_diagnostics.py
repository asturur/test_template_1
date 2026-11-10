#!/usr/bin/env python3
"""Create or decode the dedicated 1024-byte MiSTer diagnostic disk."""
import argparse
import json
import struct
from pathlib import Path

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("create", "decode"):
        cmd = sub.add_parser(name)
        cmd.add_argument("image", type=Path)
    args = parser.parse_args()
    if args.command == "create":
        with args.image.open("xb") as target:
            target.write(bytes(1024))
        print(f"Created {args.image} (1024 bytes)")
        return
    raw = args.image.read_bytes()
    if len(raw) < 1024:
        parser.error("diagnostic image is shorter than 1024 bytes")
    words = struct.unpack("<512H", raw[:1024])
    if words[0:2] != (0x4e47, 1):
        parser.error("diagnostic image has no supported snapshot")
    count, next_slot = words[5], words[6]
    if count > 64 or next_slot >= 64:
        parser.error("invalid ring metadata")
    entries = []
    for i in range(count):
        slot = (next_slot - count + i) % 64
        pos = 8 + slot * 6
        entries.append({"address": f"0x{words[pos+1]:04x}{words[pos]:04x}",
                        "data": f"0x{words[pos+3]:04x}{words[pos+2]:04x}",
                        "byte_enable": words[pos+4], "tick_low16": words[pos+5]})
    panic = None
    if words[396] == 0x504e:
        payload = struct.pack("<6H", *words[398:404])
        valid_mask = words[397] & 7
        panic = {"valid_mask": valid_mask,
                 "category_hex": payload[:8].hex(),
                 "category": (payload[:8].split(b"\0", 1)[0].decode("ascii", errors="replace")
                              if valid_mask & 3 == 3 else None),
                 "reason": struct.unpack("<I", payload[8:])[0] if valid_mask & 4 else None}
        # Kern::Fault(0x10000000) preserves the pre-filled exception context
        # instead of copying a category string (firmware50333e88..50333ef0).
        if panic["reason"] == 0x10000000:
            panic["category"] = None
            panic["exception_pc"] = (f"0x{struct.unpack('<I', payload[:4])[0]:08x}"
                                     if valid_mask & 1 else None)
            panic["exception_address"] = (f"0x{struct.unpack('<I', payload[4:8])[0]:08x}"
                                          if valid_mask & 2 else None)
    save_errors = None
    if words[404] == 0x5356:
        save_errors = {"C:": bool(words[405] & 1), "PMM": bool(words[405] & 2)}
    print(json.dumps({"panic_report": panic, "save_errors": save_errors, "fault_seen": bool(words[4] & 8),
                      "fault_reason": words[4] & 7,
                      "fault_address": f"0x{words[3]:04x}{words[2]:04x}",
                      "wrapped": bool(words[7] & 1), "dropped_events": words[392],
                      "fetch_fault_seen": bool(words[395] & 8),
                      "fetch_fault_reason": words[395] & 7,
                      "fetch_fault_address": f"0x{words[394]:04x}{words[393]:04x}",
                      "events": entries}, indent=2))

if __name__ == "__main__":
    main()
