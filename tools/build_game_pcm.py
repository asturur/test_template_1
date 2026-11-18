#!/usr/bin/env python3
"""Build a private NEM-4 4.03 PCM firmware patch and verify the original bytes."""
import argparse
import hashlib
import inspect
import json
from pathlib import Path
import struct
import subprocess

import nos_overlay
import service_firmware
import ngage_runtime_bt as runtime

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'firmware_overlays/game_pcm'
STOCK_SHA = '88fd596a23269ecb0d9f7544d540c59010d276574dbe3d0262c870c429e58329'
PAYLOAD = 0x11b6000
THUNK = 0x2c7ac0


def compile_payload(out):
    flags = ['-mcpu=arm920t', '-marm', '-Os', '-ffreestanding', '-fno-builtin',
             '-fno-unwind-tables', '-fno-asynchronous-unwind-tables',
             '-fno-common', '-Wall', '-Wextra', '-Werror']
    objects = []
    for source in ('entry.S', 'native.c', 'stream.c'):
        obj = out / f'{source}.o'
        subprocess.run(['arm-none-eabi-gcc', *flags, '-c', SOURCE / source,
                        '-o', obj], check=True)
        objects.append(obj)
    elf = out / 'game-pcm.elf'
    binary = out / 'game-pcm.bin'
    subprocess.run(['arm-none-eabi-ld', '-T', SOURCE / 'native.ld',
                    '-o', elf, *objects], check=True)
    subprocess.run(['arm-none-eabi-objcopy', '-O', 'binary', elf, binary], check=True)
    return binary.read_bytes()


def verified_backing(firmware):
    raw = bytearray(b'\xff' * service_firmware.BACKING_SIZE)
    for kind, profile in service_firmware.PROFILES.items():
        records = service_firmware.parse((firmware / profile[0]).read_bytes(), kind)
        service_firmware.apply(raw, records, kind)
    if hashlib.sha256(raw).hexdigest() != STOCK_SHA:
        raise ValueError('unexpected service backing')
    return raw


def build(out, firmware):
    raw = verified_backing(firmware)
    out.mkdir(parents=True, exist_ok=False)
    payload = compile_payload(out)
    if raw[PAYLOAD:PAYLOAD + 4096] != b'\xff' * 4096:
        raise ValueError('PCM payload page is occupied')
    if struct.unpack_from('<I', raw, THUNK)[0] != 0x514bce39:
        raise ValueError('unexpected original NOS route target')

    plain = nos_overlay.decode(raw)
    old_digest = plain[0x8f20:0x8f30]
    if hashlib.md5(plain[0x9000:0x11b5000]).digest() != old_digest:
        raise ValueError('stock firmware digest does not match')
    pointer = struct.pack('<I', 0x50000000 + PAYLOAD)
    plain[THUNK:THUNK+4] = pointer
    digest = hashlib.md5(plain[0x9000:0x11b5000]).digest()

    patched = bytearray(raw)
    patches = ((PAYLOAD, payload), (THUNK, pointer), (0x8f20, digest))
    words = []
    for offset, data in patches:
        if offset & 3 or len(data) & 3:
            raise ValueError('patch must contain aligned words')
        for i in range(0, len(data), 4):
            old = struct.unpack_from('<I', raw, offset + i)[0]
            new = struct.unpack_from('<I', data, i)[0]
            if old != new:
                words.append((offset + i, old, new))
        patched[offset:offset+len(data)] = data

    restored = bytearray(patched)
    for offset, old, _ in words:
        struct.pack_into('<I', restored, offset, old)
    if raw != restored:
        raise ValueError('undo check failed')

    manifest = dict(
        original_sha256=STOCK_SHA,
        patched_sha256=hashlib.sha256(patched).hexdigest(),
        payload_sha256=hashlib.sha256(payload).hexdigest(),
        payload_bytes=len(payload),
        original_md5=old_digest.hex(), patched_md5=digest.hex(),
        checksum_bounds_retained=True, records=sorted(words),
    )
    (out / 'backing.bin').write_bytes(patched)
    (out / 'window-dec.bin').write_bytes(plain[0xa000:0x2b3000])
    (out / 'patch.json').write_text(json.dumps(manifest, indent=2) + '\n')
    write_board_tool(out, manifest)
    print(f"{len(payload)} payload bytes, {len(words)} word changes, MD5 {digest.hex()}")


def write_board_tool(out, manifest):
    """Assemble a standalone, fresh-Hold-only tool for the field HPS."""
    source = 'import argparse, hashlib, json, mmap, os, struct, time\n'
    for name in ('BASE', 'SIZE', 'ROM_SIZE', 'ROM_SHA'):
        source += f'{name} = {getattr(runtime, name)!r}\n'
    source += f'EXIT_HOOKS = ({THUNK},)\n'
    for function in (runtime.snapshot, held_fresh, runtime.validate_image, runtime.patch_image):
        source += '\n' + inspect.getsource(function)
    source += f'\nrecords = {manifest["records"]!r}\n'
    source += f'patched_sha = {manifest["patched_sha256"]!r}\n'
    source += '''
parser = argparse.ArgumentParser(description='Volatile NEM-4 game PCM firmware bridge')
parser.add_argument('--apply', action='store_true')
args = parser.parse_args()
fd = os.open('/dev/mem', (os.O_RDWR if args.apply else os.O_RDONLY) | os.O_SYNC)
try:
    access = mmap.ACCESS_WRITE if args.apply else mmap.ACCESS_READ
    with mmap.mmap(fd, SIZE, access=access, offset=BASE) as memory:
        validate_image(memory, records)
        first = snapshot(memory)
        if not held_fresh(first):
            raise ValueError('cold core with CPU Hold and save Off is required')
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            time.sleep(.1)
            second = snapshot(memory)
            if not held_fresh(second):
                raise ValueError('core left fresh Hold before installation')
            if second[2] != first[2]:
                break
        else:
            raise ValueError('DDR recorder is not advancing')
        if args.apply:
            patch_image(memory, records)
            if hashlib.sha256(memory[:ROM_SIZE]).hexdigest() != patched_sha:
                for offset, original, patched in reversed(records):
                    struct.pack_into('<I', memory, offset, original)
                raise ValueError('patched image failed its full readback check')
        print(json.dumps(dict(fresh_held=True, applied=args.apply,
                              patched_sha256=patched_sha, words=len(records))))
finally:
    os.close(fd)
'''
    (out / 'install.py').write_text(source)


def held_fresh(words):
    # Warm reset can advance generation before the first fetch. Check the
    # retained cold-lifetime history and the physical Hold/save state instead.
    flags = words[242]
    return (words[8] == words[9] == 0 and words[13] <= 1
            and all(words[8+i] == 0 for i in (2, 4, 10, 11))
            and not (words[29] & 256) and words[30] & 1
            and (flags & 7) == 0 and flags & (1 << 4)
            and flags & (1 << 25)
            and not flags & ((1 << 6) | (1 << 7) | (1 << 10) | (1 << 26)))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--firmware', default=ROOT / 'firmware/NEM-04 v.04.03 N-GAGE',
                        type=Path)
    args = parser.parse_args()
    build(args.output, args.firmware)
