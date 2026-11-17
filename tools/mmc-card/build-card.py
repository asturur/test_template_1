#!/usr/bin/env python3
"""Build a FAT12/16 MMC from any folder, including an empty one.

Uses the frozen mkcard.py alongside this file; requires mtools.
Default: rebuild the three delivered cards. Or: build-card.py FOLDER OUTPUT_STEM
"""
from pathlib import Path
import hashlib
import json
import sys
import argparse
import mkcard

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
INPUTS = ROOT / "runtime/mmc"
OUTPUTS = ROOT / "build/mmc"

def build(source, output, size=16):
    source, output = Path(source).resolve(), Path(output).resolve()
    if not source.is_dir():
        raise ValueError('Source must be a folder')
    if output.is_relative_to(source):
        raise ValueError('Keep generated images outside the source folder')
    files, dirs, notes = mkcard.plan_tree(str(source), True)
    g = mkcard.geometry(size)
    need, roots = mkcard.usage(files, dirs)
    if need > g['clusters'] or roots > mkcard.ROOT_ENTRIES:
        raise ValueError(f'Folder exceeds the {size} MB card capacity')
    output.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(str(output) + '.img.part')
    stage.write_bytes(mkcard.blank_card(g))
    try:
        mkcard.fill(str(stage), files, dirs, 1041379200)
        data = stage.read_bytes()
        free = mkcard.verify(data, files, dirs)
        mkcard.write_card(str(output), data,
                          mkcard.folder_cid(output.name, 1041379200),
                          mkcard.folder_csd(g['mult']), bytes.fromhex('00ff8000'))
    finally:
        stage.unlink(missing_ok=True)
    manifest = dict(filesystem=f'FAT{g["bits"]}', geometry=g, free_bytes=free * mkcard.CLUSTER,
                    source_folder=str(source), notes=notes, files=[], images={})
    for cd in sorted(dirs):
        for name, path in files[cd]:
            content = Path(path).read_bytes()
            manifest['files'].append(dict(path='/'.join(cd + (name,)), bytes=len(content),
                                          sha256=hashlib.sha256(content).hexdigest()))
    for ext in ('.img', '.mmc'):
        path = Path(str(output) + ext)
        manifest['images'][path.name] = dict(bytes=path.stat().st_size,
                                           sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    Path(str(output) + '.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('%s: %d files, %d KiB free, all files read back and compared' %
          (output.name, len(manifest['files']), manifest['free_bytes'] // 1024))

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--size', type=int, choices=(16, 32, 64, 128), default=16,
                    help='card capacity in MB (default: 16)')
parser.add_argument('source', nargs='?')
parser.add_argument('output', nargs='?')
args = parser.parse_args()
if args.source is None and args.output is None:
    for folder, name in [('files', 'spmark-installer'), ('extracted-files', 'spmark-ready'),
                         ('empty-files', 'blank-fat12')]:
        build(INPUTS / folder, OUTPUTS / name, args.size)
elif args.source is not None and args.output is not None:
    build(args.source, args.output, args.size)
else:
    parser.error('SOURCE_FOLDER and OUTPUT_STEM must be supplied together')
