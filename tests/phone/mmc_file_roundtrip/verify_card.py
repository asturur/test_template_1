"""Check the exact filesystem and sector delta on the disposable 128 MB fixture."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
CARD_SHA = 'a8cc5e20918aa1b54b92504f384a0ff5c29069e91e3b1a9823fe94e18bfe65d8'
EXPECTED_PAYLOAD = bytes((i * 37 + (i >> 3) + 0x69) & 255 for i in range(1739))


def audit(path):
    return json.loads(subprocess.check_output([
        sys.executable, ROOT / 'tools/mmc-card/audit-fat.py', path,
    ]))


def verify(before, after, board_copy=False):
    original = audit(before)
    saved = audit(after)
    assert original['image_sha256'] == CARD_SHA, 'unexpected control image'
    assert not original['errors'] and not saved['errors'] and saved['fat_mirrors_equal']
    assert saved['partition'] == original['partition'] and saved['geometry'] == original['geometry']
    assert saved['allocated_clusters'] == original['allocated_clusters'] + 1
    old_files = {item['path']: item for item in original['files']}
    new_files = {item['path']: item for item in saved['files']}
    if board_copy:
        destination = '/WRITE_~1/README.TXT'
        wanted = dict(old_files['/README.TXT'], path=destination)
    else:
        destination = '/WRITE_~1/ROUNDTRP.BIN'
        wanted = dict(path=destination, bytes=len(EXPECTED_PAYLOAD), clusters=1,
                      sha256=hashlib.sha256(EXPECTED_PAYLOAD).hexdigest())
    assert new_files.pop(destination, None) == wanted, 'saved file differs from known bytes'
    assert new_files == old_files, 'other files changed'

    raw_before = before.read_bytes()
    raw_after = after.read_bytes()
    assert len(raw_after) == len(raw_before)
    sector_bytes = 512
    changed = [pos // sector_bytes for pos in range(0, len(raw_before), sector_bytes)
               if raw_before[pos:pos + sector_bytes] != raw_after[pos:pos + sector_bytes]]
    # Fixed fixture: first sector of each FAT, existing subdirectory, new file's first cluster.
    data_sectors = (wanted['bytes'] + sector_bytes - 1) // sector_bytes
    assert changed == [33, 161, 321, *range(345, 345 + data_sectors)], changed
    return dict(status='PASS', image_before=original['image_sha256'],
                image_after=saved['image_sha256'], changed_lbas=changed, file=wanted,
                preserved_files=list(old_files.values()), fat_mirrors_equal=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', type=Path)
    parser.add_argument('after', type=Path)
    parser.add_argument('--board-copy', action='store_true', help='inspect the FExplorer README.TXT copy')
    args = parser.parse_args()
    print(json.dumps(verify(args.before, args.after, args.board_copy), indent=2))
