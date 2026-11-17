#!/usr/bin/env python3
"""Compact only a completed Step5F run; retain sources and executables."""
from pathlib import Path
import argparse, gzip, hashlib, json

ROOT = Path(__file__).resolve().parents[3]

def compact(directory):
    directory = directory.resolve()
    allowed = [ROOT/'build/sim'/p for p in
               ['cpu-store-postindex', 'spmark-payload', 'jpeg-payload']]
    assert directory.parent in allowed
    if directory.parent.name != 'cpu-store-postindex':
        assert directory.name.startswith('postindex-')
    assert json.loads((directory/'result.json').read_text())['status'] == 'PASS'
    records = []
    for path in directory.glob('*.log'):
        if path.stat().st_size > 1000000:
            raw = path.read_bytes()
            path.with_suffix(path.suffix+'.gz').write_bytes(gzip.compress(raw))
            records.append(dict(path=path.name,
                                raw_sha256=hashlib.sha256(raw).hexdigest()))
            path.unlink()
    if records:
        (directory/'trace-storage.json').write_text(json.dumps(records, indent=2)+'\n')
    obj = directory/'obj'
    if obj.exists():
        for path in obj.iterdir():
            if path.suffix in ['.gch', '.o', '.a']:
                path.unlink()

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('directory', type=Path)
    compact(p.parse_args().directory)
