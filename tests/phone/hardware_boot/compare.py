#!/usr/bin/env python3
"""Compare compact boot-visible board events, allowing memory wait differences."""
import csv
import json
import sys
from collections import Counter
from pathlib import Path

hardware = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('build/sim/unit-hardware-boot-real-sdram/board.tsv')
ref_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path('build/sim/runs/milestone7-reference-present')
with hardware.open() as f:
    actual = list(csv.DictReader(f, delimiter='\t'))
with (ref_dir / 'bus.tsv').open() as f:
    reference = list(csv.DictReader(f, delimiter='\t'))
result = json.loads((ref_dir / 'result.json').read_text())
assert result['status'] == 'timeout' and result['cycles'] == 5000000, result['status']
assert result['hdl_board_claims'] == len(actual), (result['hdl_board_claims'], len(actual))
# C++ compact trace omits most scratch RAM traffic and logs flash separately.
# Compare every retained board operation and instruction fault in order.
rows = [r for r in reference if r['device'] not in ('flash_command', 'flash_identify')]
assert rows and len(rows) >= 100
index = 0
for row in rows:
    op = 'READ' if row['operation'] == 'FETCH_ERROR' else row['operation']
    while index < len(actual):
        got = actual[index]
        index += 1
        if (got['address'], got['op'].strip(), got['mask']) == (row['address'], op, row['byte_enable']):
            break
    else:
        raise AssertionError(f'missing ordered hardware event: {row}')
    error = row['device'] == 'unknown_fetch'
    assert (got['error'] == '1') == error, (row, got)
    if not error:
        mask = int(row['byte_enable'], 16)
        lanes = sum(0xff << (8 * i) for i in range(4) if mask & (1 << i))
        assert not ((int(row['data'], 16) ^ int(got['data'], 16)) & lanes), (row, got)
    # No IRQ or FIQ occurred in these early-boot fixtures; timer conformance
    # tests independently check interrupt edges on explicit logical ticks.
    assert got['irq'] == got['fiq'] == '0', got
print('PASS ordered staged/HDL boot:', len(rows), 'compact events,',
      result['hdl_board_claims'], 'shadow claims, devices', dict(Counter(r['device'] for r in rows)))
