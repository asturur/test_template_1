#!/usr/bin/env python3
"""Read native LCD screenshots from a matching HDL checkpoint, without clocking it."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'tests/phone/hardware_boot/screenshot_main.cpp'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def png(source, destination):
    header, size, maximum, pixels = source.read_bytes().split(b'\n', 3)
    assert (header, size, maximum) == (b'P6', b'176 208', b'255')
    assert len(pixels) == 176 * 208 * 3
    def chunk(kind, payload):
        return (struct.pack('>I', len(payload)) + kind + payload +
                struct.pack('>I', zlib.crc32(kind + payload) & 0xffffffff))
    rows = b''.join(b'\0' + pixels[y*528:(y+1)*528] for y in range(208))
    temporary = destination.with_suffix('.png.partial')
    temporary.write_bytes(b'\x89PNG\r\n\x1a\n' +
                         chunk(b'IHDR', struct.pack('>IIBBBBB', 176, 208, 8, 2, 0, 0, 0)) +
                         chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))
    temporary.replace(destination)
    source.unlink()


def capture(checkpoint):
    checkpoint = checkpoint.resolve()
    run = checkpoint.parent
    manifest = json.loads((run / 'manifest.json').read_text())
    identity = manifest['source_identity']
    build = ROOT / 'build/sim/logo-build' / identity[:16]
    if sha(build / 'Vtb') != manifest['binary_sha256']:
        raise ValueError('checkpoint executable changed; refusing mismatched HDL')
    image = manifest['image']  # Existing pinned image only; never pull a toolchain.
    docker = ['docker', 'run', '--rm', '--pull=never', '--network', 'none',
              '--platform', 'linux/arm64', '-v', f'{ROOT}:/work', '-w', '/work',
              '--entrypoint']
    def local(path):
        return str(path.relative_to(ROOT))
    directory = ROOT / 'build/sim/checkpoint-capture' / identity[:16] / sha(SOURCE)[:16]
    directory.mkdir(parents=True, exist_ok=True)
    binary = directory / 'capture'
    if not binary.exists():
        objects = ['Vtb__ALL.a', 'verilated.o', 'verilated_save.o', 'verilated_threads.o']
        temporary_binary = binary.with_name('capture.' + str(os.getpid()) + '.partial')
        subprocess.run(docker + ['g++', image, '-O2', '-I' + local(build),
                       '-I/usr/local/verilator/share/verilator/include',
                       '-I/usr/local/verilator/share/verilator/include/vltstd', local(SOURCE),
                       *[local(build / name) for name in objects], '-pthread', '-latomic',
                       '-o', local(temporary_binary)], check=True)
        temporary_binary.replace(binary)
    screens = ROOT / 'build/sim/screens' / (run.name + '-checkpoints')
    screens.mkdir(parents=True, exist_ok=True)
    output = screens / checkpoint.name
    record = output.with_suffix('.json')
    hashes = {suffix: sha(Path(str(checkpoint) + suffix)) for suffix in ('.cpu', '.host')}
    if record.exists():
        old = json.loads(record.read_text())
        if old.get('source_identity') == identity and old.get('checkpoint_sha256') == hashes and all(
                Path(str(output) + '-' + label + '.png').is_file()
                for label in ('framebuffer', 'scanout')):
            return output
    subprocess.run(docker + ['/work/' + local(binary), image,
                            local(checkpoint), local(output)], check=True)
    metadata = json.loads(record.read_text())
    for label in ('framebuffer', 'scanout'):
        png(Path(str(output) + '-' + label + '.ppm'), Path(str(output) + '-' + label + '.png'))
    # Verify observation has not modified either source checkpoint file.
    assert hashes == {suffix: sha(Path(str(checkpoint) + suffix)) for suffix in hashes}
    metadata.update(source_identity=identity, checkpoint=str(checkpoint.relative_to(ROOT)),
                    checkpoint_sha256=hashes, observer_sha256=sha(SOURCE),
                    cycles=int(checkpoint.name.split('-')[-1]))
    temporary = record.with_suffix('.json.partial')
    temporary.write_text(json.dumps(metadata, indent=2) + '\n')
    temporary.replace(record)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path', type=Path, help='checkpoint prefix, or run directory with --watch')
    parser.add_argument('--watch', action='store_true', help='render completed checkpoint pairs as they appear')
    args = parser.parse_args()
    if not args.watch:
        print(capture(args.path))
        return
    seen = set()
    while True:
        for host in sorted(args.path.glob('checkpoint-*.host')):
            prefix = host.with_suffix('')
            if prefix not in seen and prefix.with_suffix('.cpu').is_file():
                print(capture(prefix), flush=True)
                seen.add(prefix)
        if (args.path / 'result.json').exists():
            return
        time.sleep(2)  # Filesystem-only sidecar; no agent/log monitoring.


if __name__ == '__main__':
    main()
