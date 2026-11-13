#!/usr/bin/env python3
"""Request a held Nokia key in a running frozen phone simulation; no HDL edit."""
import argparse
import json
import time
from pathlib import Path

KEYS = dict(up=0, down=1, left=2, right=3, ok=4, left_soft=5,
            menu=6, clear=7, radio=8, right_soft=9, star=10, hash=11,
            shift=21, send=23, end=24, music=25, power=26)
KEYS.update({str(n): 11 + n for n in range(1, 10)})
KEYS['0'] = 22


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path)
    parser.add_argument('key', help='key name, comma-separated chord, or release')
    parser.add_argument('--milliseconds', type=int, default=150)
    args = parser.parse_args()
    manifest = json.loads((args.run / 'manifest.json').read_text())
    if not manifest.get('interactive_keys'):
        parser.error('this run has no serialized interactive key input')
    if args.milliseconds <= 0:
        parser.error('hold duration must be positive')
    mask = 0
    for name in args.key.lower().split(','):
        if name == 'release':
            if args.key.lower() != 'release':
                parser.error('release cannot be combined with a key')
            break
        if name not in KEYS:
            parser.error('unknown key; choose ' + ', '.join(KEYS))
        mask |= 1 << KEYS[name]
    hold = manifest['sys_clk_hz'] * args.milliseconds // 1000 if mask else 0
    if not 0 <= hold < 2**64:
        parser.error('hold duration exceeds the simulation counter')
    request = args.run / 'key-command.txt'
    previous = int(request.read_text().split()[0]) if request.exists() else 0
    sequence = max(time.time_ns(), previous + 1)
    temporary = request.with_suffix('.txt.partial')
    temporary.write_text(f'{sequence} {mask:x} {hold}\n')
    temporary.replace(request)
    with (args.run / 'key-requests.jsonl').open('a') as journal:
        journal.write(json.dumps(dict(id=sequence, key=args.key, mask=mask, hold=hold)) + '\n')
    print(f'Requested {args.key}; {args.milliseconds if mask else 0} ms of phone time. '
          'KEY_APPLIED in progress.log confirms delivery.')


if __name__ == '__main__':
    main()
