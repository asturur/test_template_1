#!/usr/bin/env python3
"""Capture the observed full-screen white clear, without fabricating later frames.

This intentionally recognizes only the recorded full-screen all-ones transfer.
It refuses unknown or subsequent framebuffer writes until their format is decoded.
"""
import argparse
import hashlib
import json
import struct
import zlib
from pathlib import Path
from analyze_lcd_trace import analyze

WIDTH, HEIGHT = 176, 208
HEADER, WORDS = 0x8924d67f, 18304
WHITE_HASH = hashlib.sha256(b'\xff\xff\xff\xff' * WORDS).hexdigest()


def chunk(kind, content):
    return struct.pack('>I',len(content)) + kind + content + struct.pack('>I',zlib.crc32(kind+content)&0xffffffff)


def capture(trace, out):
    result_path = trace.with_name('result.json')
    if not result_path.is_file() or result_path.stat().st_size == 0:
        raise ValueError('A completed simulation result is required; trace may still be buffered')
    result = json.loads(result_path.read_text())
    summary = analyze(trace)
    writes = [x for x in summary['commands'] if x['value'] == 0x5c]
    if len(writes) != 1:
        raise ValueError('Expected exactly one observed memory-write command; later screen state is unknown')
    candidates = [t for t in summary['transfers'] if t['cycle'] > writes[0]['cycle'] and t['word_count']]
    if not candidates:
        raise ValueError('No data after memory-write command')
    image_transfer = candidates[0]
    if (image_transfer['header'] != HEADER or image_transfer['word_count'] != WORDS or
        image_transfer['data_sha256_le_words'] != WHITE_HASH):
        raise ValueError('Memory-write data is not the known uniform clear; pixel decoding is required')
    if not summary['commands'] or summary['commands'][-1]['value'] != 0xaf or summary['commands'][-1]['cycle'] <= image_transfer['cycle']:
        raise ValueError('Latest observed LCD command is not display-on following the clear')
    display_on_cycle = summary['commands'][-1]['cycle']
    if any(t['cycle'] > display_on_cycle and t['word_count'] for t in summary['transfers']):
        raise ValueError('Unrecognized LCD data after display-on; current screen is unknown')
    pixels = b''.join(b'\0' + b'\xff\xff\xff' * WIDTH for _ in range(HEIGHT))
    png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR',struct.pack('>IIBBBBB',WIDTH,HEIGHT,8,2,0,0,0)) +
           chunk(b'IDAT',zlib.compress(pixels,9)) + chunk(b'IEND',b''))
    out.mkdir(parents=True,exist_ok=True)
    (out/'screen.png').write_bytes(png)
    info = dict(source_trace=str(trace), result_status=result.get('status'), cycle=image_transfer['cycle'],
                transfer_header=hex(HEADER), data_words=WORDS, pixels=WIDTH*HEIGHT,
                interpretation='All-ones full-screen clear interpreted as white; LCD inversion, pixel format and hardware behavior are unverified.',
                trace_sha256=hashlib.sha256(trace.read_bytes()).hexdigest(), png_sha256=hashlib.sha256(png).hexdigest(),
                capture_script_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                analyzer_sha256=hashlib.sha256(Path(__file__).with_name('analyze_lcd_trace.py').read_bytes()).hexdigest(),
                capture_scope='completed trace through final stop; unknown nonuniform memory writes are rejected')
    (out/'screen.json').write_text(json.dumps(info,indent=2)+'\n')
    return info


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trace',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    try:
        result=capture(args.trace,args.output)
        print(f"Captured assumed white {WIDTH}x{HEIGHT} clear to {args.output/'screen.png'}; source cycle {result['cycle']}")
    except (OSError,ValueError,KeyError) as exc:
        raise SystemExit(str(exc))
