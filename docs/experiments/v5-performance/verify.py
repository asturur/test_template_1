#!/usr/bin/env python3
"""Apply the archived patches to private Git indexes and verify recorded provenance."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


CATALOG = Path(__file__).resolve().parent


def git(root, *args, env=None):
    proc = subprocess.run(
        ['git', '-C', str(root), *args], check=True, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    return proc.stdout


def check(root, entry, alternate, work):
    with tempfile.TemporaryDirectory(prefix='patch-check-', dir=work) as temp:
        private = Path(temp)
        objects = private / 'objects'
        objects.mkdir()
        env = os.environ | {
            'GIT_INDEX_FILE': str(private / 'index'),
            'GIT_OBJECT_DIRECTORY': str(objects),
            'GIT_ALTERNATE_OBJECT_DIRECTORIES': str(alternate),
        }
        git(root, 'read-tree', entry['base'], env=env)
        for name, digest in zip(entry['patches'], entry['sha256'], strict=True):
            patch = (CATALOG / name).resolve()
            raw = patch.read_bytes()
            assert hashlib.sha256(raw).hexdigest() == digest, name
            assert b'GIT binary patch' not in raw and b'Binary files ' not in raw, name
            git(root, 'apply', '--cached', '--check', str(patch), env=env)
            git(root, 'apply', '--cached', str(patch), env=env)
        paths = [part.decode() for part in git(root, 'diff', '--cached', '--name-only', '-z',
                                              entry['base'], env=env).split(b'\0') if part]
        assert paths, entry['id']
        if 'affected_paths' in entry:
            assert paths == entry['affected_paths'], (entry['id'], paths)
        if 'target' in entry:
            for path in paths:
                actual = git(root, 'rev-parse', ':' + path, env=env)
                expected = git(root, 'rev-parse', entry['target'] + ':' + path, env=env)
                assert actual == expected, (entry['id'], path, actual, expected)
        for path, expected in entry.get('measured_sha256', {}).items():
            actual = hashlib.sha256(git(root, 'show', ':' + path, env=env)).hexdigest()
            assert actual == expected, (entry['id'], path, actual, expected)
    return len(paths)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('id', nargs='*', help='verify selected catalog IDs, or all by default')
    args = parser.parse_args()
    root = Path(git(CATALOG, 'rev-parse', '--show-toplevel').decode().strip())
    rows = json.loads((CATALOG / 'manifest.json').read_text())
    requested = set(args.id)
    available = {row['id'] for row in rows}
    if requested - available:
        parser.error('Unknown IDs: ' + ', '.join(sorted(requested - available)))

    alternate = Path(git(root, 'rev-parse', '--path-format=absolute', '--git-path', 'objects').decode().strip())
    scratch = root / 'scratch'
    scratch.mkdir(exist_ok=True)
    # The temporary indexes and object stores both live under the project's scratch.
    work = scratch / 'v5-performance-validation'
    work.mkdir(exist_ok=True)
    totals = {}
    for row in rows:
        if requested and row['id'] not in requested:
            continue
        try:
            count = check(root, row, alternate, work)
        except subprocess.CalledProcessError as exc:
            raise RuntimeError(f'{row["id"]}: {exc.stderr.decode().strip()}') from exc
        kind = row['kind']
        totals[kind] = totals.get(kind, 0) + 1
        print(f'{row["id"]}: {count} paths verified against {row["base"][:7]}')
    print(f'PASS {sum(totals.values())} archive entries')


if __name__ == '__main__':
    main()
