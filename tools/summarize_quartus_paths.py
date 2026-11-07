#!/usr/bin/env python3
"""Summarize TimeQuest path CSV by endpoint block without dumping long routes."""
import argparse
import csv
from collections import defaultdict
from decimal import Decimal
from pathlib import Path

BLOCKS = ('arm920_cache_tags', 'arm920_cache_bank', 'arm920_cache_access',
          'arm920_write_buffer', 'ngage_boot_regs', 'ngage_timers',
          'ngage_sparse_regs', 'ngage_icu', 'ngage_upp_peripherals', 'ngage_debug_video',
          'ngage_debug_monitor', 'ngage_loader', 'ngage_save_manager',
          'ngage_diagnostics', 'ngage_sdram_adapter', 'jtframe_sdram64')

def block(node):
    for name in BLOCKS:
        if name + ':' in node:
            return name
    # Keep ZAP submodules individually visible rather than collapsing the CPU.
    for part in reversed(node.split('|')[:-1]):
        if ':' in part:
            return part.split(':', 1)[0]
    return 'top/other'

def summary(path):
    with path.open(newline='') as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise ValueError('empty path CSV')
    required = {'slack_ns', 'data_delay_ns', 'logic_levels', 'from_node', 'to_node'}
    if not required <= rows[0].keys():
        raise ValueError('missing path CSV columns')
    rows.sort(key=lambda r: Decimal(r['slack_ns']))
    groups = defaultdict(list)
    for r in rows:
        for field in ('slack_ns', 'data_delay_ns', 'logic_levels'):
            Decimal(r[field])
        groups[(block(r['from_node']), block(r['to_node']))].append(r)
    lines = [f'# Worst setup paths ({len(rows)} exported)', '',
             'One worst path per endpoint; this is a diagnostic subset, not a full timing sign-off.', '',
             '| From block | To block | Paths | Worst slack ns | Max data delay ns | Max logic levels |',
             '| --- | --- | ---: | ---: | ---: | ---: |']
    for (src, dst), members in sorted(groups.items(), key=lambda g: Decimal(g[1][0]['slack_ns'])):
        lines.append(f'| {src} | {dst} | {len(members)} | {members[0]["slack_ns"]} | '
                     f'{max(Decimal(r["data_delay_ns"]) for r in members)} | '
                     f'{max(Decimal(r["logic_levels"]) for r in members)} |')
    lines += ['', '## Worst ten node pairs', '']
    for r in rows[:10]:
        lines += [f'- {r["slack_ns"]} ns, {r["logic_levels"]} levels, {r["data_delay_ns"]} ns data: '
                  f'`{r["from_node"]}` → `{r["to_node"]}`']
    return '\n'.join(lines) + '\n'

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('csv', type=Path)
    p.add_argument('--output', type=Path)
    a = p.parse_args()
    try:
        text = summary(a.csv)
    except (OSError, ValueError, ArithmeticError) as e:
        p.exit(1, f'Path summary failed: {e}\n')
    if a.output:
        a.output.write_text(text)
        print(f'Wrote {a.output}')
    else:
        print(text, end='')

if __name__ == '__main__':
    main()
