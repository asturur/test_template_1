"""Prepare a volatile, observation-only reset trace for stock NEM-4 4.03."""
import hashlib
import inspect
import json
from pathlib import Path
import struct
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import ngage_runtime_bt as runtime
from build_game_pcm import verified_backing
from build_virtual_sim import decode16, encode16, rules
from nos_overlay import decode
from prepare_native_observer import held_fresh

PAD = 0x316a00
NOS_BASE = 0x51400000
NOS_HOOK = 0xc1144
PLAT_HOOK = 0x324dc4
THUMB_HOOKS = {
    NOS_HOOK: ("nos_reset", "05701448"),
    0xc2154: ("nos_poweroff", "00200870"),
    0x19a5f0: ("nos_mtc", "020e0906"),
}
RTC_HOOK = 0xa6424
OUTPUT = ROOT / "build" / "mister" / "reset-observer"


def build_payload():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    binary, elf, obj = (OUTPUT / f"trace.{ext}" for ext in ("bin", "elf", "o"))
    subprocess.run(["arm-none-eabi-as", "-mcpu=arm920t", "-o", obj, HERE / "trace.S"], check=True)
    subprocess.run(["arm-none-eabi-ld", "-Ttext=0x51716a00", "-e", "nos_reset", "-o", elf, obj], check=True)
    subprocess.run(["arm-none-eabi-objcopy", "-O", "binary", elf, binary], check=True)
    symbols = {name: int(address, 16) for line in subprocess.check_output(
        ["arm-none-eabi-nm", elf], text=True).splitlines()
        if len(parts := line.split()) == 3
        for address, _, name in [parts]}
    return binary.read_bytes(), symbols

def prepare():
    raw = verified_backing(ROOT / "firmware" / "NEM-04 v.04.03 N-GAGE")
    stock = decode(raw)
    digest = stock[0x8f20:0x8f30]
    if hashlib.md5(stock[0x9000:0x11b5000]).digest() != digest:
        raise ValueError("stock checksum mismatch")
    payload, symbols = build_payload()
    if len(payload) % 4 or PAD + len(payload) > 0x317000:
        raise ValueError("trace payload does not fit NOS padding")
    if raw[PAD:PAD + len(payload)] != bytes(len(payload)):
        raise ValueError("NOS padding differs from stock")
    if stock[PLAT_HOOK:PLAT_HOOK + 4].hex() != "2000a0e3":
        raise ValueError("Plat::Reset hook bytes changed")
    if stock[RTC_HOOK:RTC_HOOK + 4].hex() != "0fe0a0e1":
        raise ValueError("NOS RTC call bytes changed")
    patched = bytearray(raw)
    patched[PAD:PAD + len(payload)] = payload
    stock[PAD:PAD + len(payload)] = payload

    rule = rules()
    for hook, (name, expected) in THUMB_HOOKS.items():
        if stock[hook:hook + 4].hex() != expected:
            raise ValueError(f"{name} hook bytes changed")
        delta = (symbols[name] & ~1) - (NOS_BASE + hook + 4)
        if delta & 1 or not -(1 << 22) <= delta < 1 << 22:
            raise ValueError(f"{name} Thumb BL is out of range")
        halves = (0xf000 | ((delta >> 12) & 0x7ff), 0xf800 | ((delta >> 1) & 0x7ff))
        for off, half in zip((hook, hook + 2), halves):
            struct.pack_into("<H", stock, off, half)
            struct.pack_into("<H", patched, off, encode16(half, off, rule))

    for hook, name in ((PLAT_HOOK, "plat_reset"), (RTC_HOOK, "nos_rtc_call")):
        delta = symbols[name] - NOS_BASE - hook - 8
        if delta & 3 or not -(1 << 25) <= delta < 1 << 25:
            raise ValueError(f"{name} ARM branch is out of range")
        branch = 0xea000000 | ((delta >> 2) & 0xffffff)
        struct.pack_into("<I", stock, hook, branch)
        if hook == RTC_HOOK:
            struct.pack_into("<2H", patched, hook, encode16(branch & 0xffff, hook, rule),
                             encode16(branch >> 16, hook + 2, rule))
        else:
            struct.pack_into("<I", patched, hook, branch)
    patched[0x8f20:0x8f30] = hashlib.md5(stock[0x9000:0x11b5000]).digest()
    hooks = (*THUMB_HOOKS, PLAT_HOOK, RTC_HOOK)
    offsets = [*hooks, *range(0x8f20, 0x8f30, 4), *range(PAD, PAD + len(payload), 4)]
    records = [(offset, struct.unpack_from("<I", raw, offset)[0],
                struct.unpack_from("<I", patched, offset)[0]) for offset in sorted(offsets)]
    report = dict(records=len(records), original=runtime.ROM_SHA,
                  instrumented=hashlib.sha256(patched).hexdigest(), symbols=symbols,
                  stock_md5=digest.hex(), new_md5=patched[0x8f20:0x8f30].hex())
    script = "import argparse,hashlib,json,mmap,os,struct,time\n"
    for name in ("BASE", "SIZE", "ROM_SIZE", "ROM_SHA"):
        script += f"{name} = {getattr(runtime, name)!r}\n"
    script += f"EXIT_HOOKS = {hooks!r}\n"
    for function in (runtime.snapshot, held_fresh, runtime.validate_image, runtime.patch_image):
        script += "\n" + inspect.getsource(function)
    script += f"\nrecords = {records!r}\nreport = {report!r}\n"
    script += """
parser = argparse.ArgumentParser(description='Observe the native reset caller and reason')
parser.add_argument('--apply', action='store_true')
args = parser.parse_args()
mode = os.O_RDWR if args.apply else os.O_RDONLY
with os.fdopen(os.open('/dev/mem', mode | os.O_SYNC), 'r+b' if args.apply else 'rb') as dev:
    access = mmap.ACCESS_WRITE if args.apply else mmap.ACCESS_READ
    with mmap.mmap(dev.fileno(), SIZE, access=access, offset=BASE) as memory:
        validate_image(memory, records)
        first = snapshot(memory)
        report['fresh_held'] = bool(held_fresh(first))
        report['applied'] = False
        if args.apply:
            if not held_fresh(first):
                raise SystemExit('Requires fresh CPU Hold and Background save Off.')
            deadline = time.monotonic() + 3
            while True:
                time.sleep(.1)
                newest = snapshot(memory)
                if not held_fresh(newest):
                    raise SystemExit('CPU Hold changed before the observer could be applied.')
                if newest[2] != first[2]:
                    break
                if time.monotonic() >= deadline:
                    raise SystemExit('DDR observer snapshot is not advancing.')
            patch_image(memory, records)
            if hashlib.sha256(memory[:ROM_SIZE]).hexdigest() != report['instrumented']:
                raise SystemExit('Instrumented ROM failed full readback.')
            report['applied'] = True
        print(json.dumps(report))
"""
    (OUTPUT / "observer.py").write_text(script)
    (OUTPUT / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    prepare()
