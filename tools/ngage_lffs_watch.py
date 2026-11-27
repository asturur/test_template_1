#!/usr/bin/env python3
"""Watch a saved C: image over Samba/local path or SSH; decode changed copies.

Only persisted guest data is visible. Each successful extraction is preserved;
partial/corrupt saves never replace the latest successful log view. No input
write or filesystem repair is performed. Requires ngage_lffs_extract.py deps.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shlex
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def now():
    return datetime.now(timezone.utc).isoformat()


def read_image(path, ssh=None):
    if not ssh:
        return Path(path).read_bytes()
    result = subprocess.run(['ssh', ssh, 'cat -- '+shlex.quote(path)],
                            capture_output=True, check=True, timeout=20)
    return result.stdout


def display_text(data):
    if data.startswith((b'\xff\xfe', b'\xfe\xff')):
        return data.decode('utf-16', errors='replace')
    if len(data) > 4 and data[1::2].count(0) > len(data)//4:
        return data.decode('utf-16-le', errors='replace')
    return data.decode('utf-8', errors='replace')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('image', help='local/Samba path, or remote path with --ssh')
    ap.add_argument('--out', required=True, type=Path)
    ap.add_argument('--ssh', help='SSH destination, e.g. root@192.168.1.176; use SSH keys/config')
    ap.add_argument('--interval', type=float, default=10)
    ap.add_argument('--count', type=int, default=0, help='number of polls;0 means until interrupted')
    ap.add_argument('--rom', type=Path, default=ROOT/'firmware/SYM.ROM')
    ap.add_argument('--reference', type=Path, default=ROOT/'scratch/fresh-c-investigation/ngvm4')
    args = ap.parse_args()
    if args.interval < 1 or args.count < 0:
        ap.error('interval must be at least1 second; count must be non-negative')
    out = args.out.resolve()
    if out.exists():
        ap.error('output must not already exist; preserves earlier sessions')
    out.mkdir(parents=True)
    journal = out/'events.jsonl'
    work = None
    last_sha = None
    last_logs = {}
    polls = 0

    def event(kind, **values):
        record = {'time_utc': now(), 'event': kind, **values}
        with journal.open('a') as target:
            target.write(json.dumps(record)+'\n')
        return record

    event('start', image=args.image, ssh=args.ssh, interval_seconds=args.interval)
    try:
        while args.count == 0 or polls < args.count:
            polls += 1
            started = time.monotonic()
            capture = out/f'capture-{polls:06d}'
            try:
                raw = read_image(args.image, args.ssh)
                if len(raw) != 4194304:
                    raise ValueError('saved C: image must be exactly4 MiB')
                sha = hashlib.sha256(raw).hexdigest()
                if sha != last_sha:
                    # Two matching reads reduce torn-copy exposure. This is not
                    # a guest filesystem transaction barrier; the reader must
                    # still reject corrupt/incomplete filesystem records.
                    time.sleep(0.2)
                    if hashlib.sha256(read_image(args.image, args.ssh)).hexdigest() != sha:
                        raise ValueError('image changed while copying; retry next poll')
                    copied = out/f'input-{polls:06d}.vhd'
                    copied.write_bytes(raw)
                    cmd = [sys.executable, str(ROOT/'tools/ngage_lffs_extract.py'), str(copied),
                           '--out', str(capture), '--rom', str(args.rom),
                           '--reference', str(args.reference)]
                    if work:
                        cmd += ['--reuse-work', str(work)]
                    with (out/f'poll-{polls:06d}.log').open('wb') as log:
                        subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT,
                                       check=True, timeout=150)
                    manifest = json.loads((capture/'manifest.json').read_text())
                    if (capture/'.work/prepared.json').exists():
                        work = capture/'.work'
                    logs = {}
                    for item in manifest['files']:
                        name = item['path']
                        data = (capture/'files'/item['relative_path']).read_bytes()
                        logs[name] = display_text(data)
                    lines = [f'Saved-image logs captured {now()}', f'Image SHA-256: {sha}',
                             'This is persisted guest data, not a live process/RAM trace.', '']
                    for name, text in logs.items():
                        lines += ['===== '+name+' =====', text, '']
                        if last_logs.get(name) != text:
                            print(f'[{now()}] {name}', flush=True)
                            print(text[:16384], flush=True)
                            if len(text) > 16384:
                                print('(console truncated; full log is in the capture)', flush=True)
                    tmp = out/'latest-logs.txt.new'
                    tmp.write_text('\n'.join(lines))
                    tmp.replace(out/'latest-logs.txt')
                    latest = {'time_utc': now(), 'capture': str(capture), 'source_sha256': sha,
                              'entries': len(manifest['entries']), 'log_files': list(logs),
                              'status': manifest['status']}
                    tmp = out/'latest.json.new'
                    tmp.write_text(json.dumps(latest, indent=2)+'\n')
                    tmp.replace(out/'latest.json')
                    event('decoded', **latest)
                    last_sha, last_logs = sha, logs
                    print(f'[{now()}] decoded {len(manifest["entries"])} entries, {len(logs)} log/text files', flush=True)
                else:
                    event('unchanged', source_sha256=sha)
            except (OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
                event('retry', error=str(exc), capture=str(capture))
                print(f'[{now()}] waiting for a readable, saved image: {exc}', file=sys.stderr, flush=True)
            if args.count == 0 or polls < args.count:
                time.sleep(max(0, args.interval-(time.monotonic()-started)))
    except KeyboardInterrupt:
        event('stopped', polls=polls)


if __name__ == '__main__':
    main()
