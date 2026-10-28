#!/usr/bin/env python3
"""Summarize firmware LCD writes without assuming controller or pixel format."""
import argparse
import csv
import hashlib
import json
from pathlib import Path


def analyze(path):
    transfers = []
    current = None
    commands = []
    controls = []
    with path.open(newline='') as stream:
        for row in csv.DictReader(stream, delimiter='\t'):
            if row.get('device') != 'lcd_probe_transport' or row.get('operation') != 'WRITE':
                continue
            address, data = int(row['address'], 16), int(row['data'], 16)
            cycle = int(row['cycle'])
            if address == 0x0c121204:
                controls.append(dict(cycle=cycle, value=data))
            elif address == 0x0c121200:
                current = dict(cycle=cycle, header=data, word_count=0, first_words=[], unique_words=set(),
                               digest=hashlib.sha256())
                transfers.append(current)
            elif address == 0x0c121208:
                if current is None:
                    raise ValueError('LCD data before a recorded transfer header')
                current['word_count'] += 1
                if len(current['first_words']) < 8:
                    current['first_words'].append(data)
                current['unique_words'].add(data)
                current['digest'].update(data.to_bytes(4, 'little'))
                if current['header'] == 0x09200000:
                    commands.append(dict(cycle=cycle, value=data))
    for transfer in transfers:
        transfer['unique_word_count'] = len(transfer.pop('unique_words'))
        transfer['data_sha256_le_words'] = transfer.pop('digest').hexdigest()
    return dict(trace=str(path), controls=controls, commands=commands, transfers=transfers,
                caveat='Raw transfer summary; command meaning and pixel format are not verified.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trace',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    result=analyze(args.trace)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    print(f"{len(result['commands'])} command words; {len(result['transfers'])} transfer headers")
    for item in result['transfers']:
        if item['word_count'] >= 100:
            print(f"cycle {item['cycle']}: header {item['header']:#x}, {item['word_count']} words, {item['unique_word_count']} unique")


if __name__ == '__main__':
    main()
