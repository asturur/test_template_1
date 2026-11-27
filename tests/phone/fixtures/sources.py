#!/usr/bin/env python3
"""Record or verify hashes of source inputs for the reference board profiles."""
import hashlib
import json
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[3]
PATHS = [*sorted((ROOT / 'scratch/current-boot/board').glob('*')),
         *sorted((ROOT / 'scratch/simif-board/board').glob('*')),
         ROOT / 'scratch/live-controls/boot_profile.cpp',
         ROOT / 'scratch/live-controls/boot_profile.h',
         ROOT / 'scratch/simif-investigation/test_card.h',
         ROOT / 'scratch/simif-board/run.py',
         ROOT / 'scratch/simif-board/build.py']
manifest = ROOT / 'tests/phone/fixtures/source-hashes.json'
actual = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
          for p in PATHS if p.is_file()}
if sys.argv[1:] == ['--record']:
    manifest.write_text(json.dumps(actual, indent=2, sort_keys=True) + '\n')
else:
    expected = json.loads(manifest.read_text())
    if actual != expected:
        for name in sorted(set(actual) | set(expected)):
            if actual.get(name) != expected.get(name): print('changed:', name)
        raise SystemExit(1)
    print(f'PASS {len(actual)} reference source hashes')
