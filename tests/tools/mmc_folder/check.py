#!/usr/bin/env python3
"""Synthetic end-to-end folder-card check; requires Python 3 and mtools."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
TOOLS = ROOT / 'tools/mmc-card'
OUTPUT = ROOT / 'build/mmc-tests'
OUTPUT.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='folder-', dir=OUTPUT) as temporary:
    work = Path(temporary)
    source = work / 'files'
    (source / 'nested').mkdir(parents=True)
    fixtures = {
        'A long example filename.txt': b'FAT12 long filename check\n',
        'nested/MULTI.BIN': bytes(range(256)) * 70,
    }
    for relative, content in fixtures.items():
        (source / relative).write_bytes(content)
    stem = work / 'card'
    built = subprocess.run([sys.executable, str(TOOLS / 'build-card.py'),
                            str(source), str(stem)], capture_output=True, text=True)
    if built.returncode:
        raise SystemExit(built.stdout + built.stderr)
    card = stem.with_suffix('.mmc')
    audit = json.loads(subprocess.check_output(
        [sys.executable, str(TOOLS / 'audit-fat.py'), str(card)]))
    assert not audit['errors'] and not audit['warnings'], audit
    assert audit['geometry']['fat_bits'] == 12
    assert audit['file_count'] == len(fixtures)
    assert sorted((f['bytes'], f['sha256']) for f in audit['files']) == sorted(
        (len(content), hashlib.sha256(content).hexdigest()) for content in fixtures.values())
    inspection = json.loads(subprocess.check_output(
        [sys.executable, str(ROOT / 'tools/ngage_mmc_image.py'), 'inspect', str(card)]))
    assert inspection['extent']['complete_payload']
    assert inspection['identity']['capacity_bytes'] == card.stat().st_size - 512
    result = dict(result='pass', cases=['long filename', 'nested directory',
                  'multi-cluster file', 'independent allocation/hash audit',
                  'MMC footer, CRC and capacity'], image_sha256=audit['image_sha256'])
    (OUTPUT / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
print('Folder-card check passed; temporary fixture/images removed')
