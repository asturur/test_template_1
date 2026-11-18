#!/usr/bin/env python3
"""Audit a completed replay and publish compact schedules without original code."""
import argparse
import gzip
import json
import re
from collections import Counter
from pathlib import Path

from workload import PIXELS, digest

ROOT = Path(__file__).resolve().parents[3]
BUCKETS = ['read_stall', 'write_stall', 'load_lock', 'shift_lock', 'empty', 'other']


def read_log(path):
    return path.read_text() if path.exists() else gzip.decompress(path.with_suffix('.log.gz').read_bytes()).decode()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('run', type=Path)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    args.run = args.run.resolve()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    result = json.loads((args.run/'result.json').read_text())
    assert result['status']=='PASS'
    for row in result['rows']:
        assert len(row['windows'])==7 and row['repeats_equal']==2
        for w in row['windows'][2:]:
            assert w['instructions']==20*PIXELS
            assert w['issues']==20*PIXELS+1
            assert w['ram_writes']==w['accepts']==w['store_retires']==PIXELS
            assert w['mla_s2_exposed']==PIXELS and w['mla_busy']==4*PIXELS
            assert w['reads']==w['writes']==w['lines']==w['beats']==0
            assert sum(w[k] for k in BUCKETS)==w['cycles']
            assert w['last_ram']<=w['last_store_retire']<=w['cycles']
    text = read_log(args.run/'forward-0-0-0.log')
    edges = [dict((k, int(v, 16) if k in ['addr', 'ram'] else int(v))
                  for k, v in re.findall(r'(\w+)=(\w+)', line))
             for line in text.splitlines() if line.startswith('SPAN_EDGE ')]
    assert edges and [e['t'] for e in edges]==list(range(len(edges)))
    issues = [e for e in edges if e['pop']]
    assert all(e['opc']==4*(i%20) for i, e in enumerate(issues))
    representatives = []
    for pixel in [7, 8, 13, 14]:
        start, end = issues[pixel*20]['t'], issues[(pixel+1)*20]['t']
        es = [e for e in edges if start<=e['t']<end]
        requests = []
        for e in es:
            if e['rd'] or e['wr']:
                key = [e['offerpc'], e['rd'], e['wr'], hex(e['addr'])]
                if not requests or requests[-1]['key']!=key:
                    requests.append(dict(key=key, first_offer=e['t']-start, accepts=[], acks=[]))
                for signal, label in [('accept','accepts'), ('ack','acks')]:
                    if e[signal]:
                        requests[-1][label].append(e['t']-start)
        counts = Counter()
        for e in es:
            bucket = ('write_stall' if e['wr'] else 'read_stall') if e['data'] else (
                ('load_lock' if e['ll'] else 'shift_lock') if e['oval'] and e['lock'] else (
                    'empty' if not e['oval'] else 'other'))
            counts[bucket] += 1
        assert sum(counts.values())==end-start
        representatives.append(dict(pixel=pixel, start=start, next_iteration=end,
                                    cycles=end-start, exclusive_buckets=dict(counts),
                                    issues=[dict(offset=e['opc'], t=e['t']-start)
                                            for e in issues[pixel*20:(pixel+1)*20]],
                                    requests=requests,
                                    ram=[dict(t=e['t']-start, mask=hex(e['ram'])) for e in es if e['ram']],
                                    mla=[dict(t=e['t']-start, state=e['multstate'],
                                              busy=e['shstall'], dependency=e['sl'], data_stall=e['data'])
                                         for e in es if 19<=e['t']-start<=25]))
    journal = ('\n'.join(line for line in text.splitlines() if line.startswith('SPAN_EDGE '))+'\n').encode()
    journal_path = args.output.with_suffix('.events.json.gz')
    journal_path.write_bytes(gzip.compress(json.dumps(edges,separators=(',',':')).encode(),mtime=0))
    cpu_files = {n: s for n, s in result['manifest']['source']['files'].items()
                 if n.startswith('rtl/') and Path(n).suffix in ['.v', '.sv', '.svh']}
    assert len(cpu_files)==60
    assert all(digest((ROOT/n).read_bytes())==sha for n, sha in cpu_files.items())
    compiler_receipt = args.run/'compiler-inputs.json'
    journal_file = args.run/'obj/Vbench__verFiles.dat'
    if journal_file.exists():
        names = set(re.findall(r'^S[^\n]*"/work/[^"\n]*/source/(rtl/[^"\n]+)"',
                               journal_file.read_text(), re.M))
        compiler_inputs = {n: cpu_files[n] for n in sorted(names)}
        assert len(compiler_inputs)==51
        compiler_receipt.write_text(json.dumps(compiler_inputs,indent=2,sort_keys=True)+'\n')
    else:
        compiler_inputs = json.loads(compiler_receipt.read_text())
    assert len(compiler_inputs)==51 and all(cpu_files[n]==sha for n,sha in compiler_inputs.items())
    assert digest((args.run/'tb.v').read_bytes())==result['manifest']['harness_sha256']
    assert digest((args.run/'observe.vh').read_bytes())==result['manifest']['observer_sha256']
    result.update(run=str(args.run.relative_to(ROOT)), representatives=representatives,
                  frozen_rtl_header_count=len(cpu_files), frozen_rtl_headers_match_current_master=True,
                  compiler_read_rtl_header_sha256=compiler_inputs,
                  trace_edges=len(edges), trace_text_sha256=digest(journal),
                  compressed_events_sha256=digest(journal_path.read_bytes()),
                  analyzer_sha256=digest(Path(__file__).read_bytes()),
                  recommendation=dict(experiment='Capture registered DSP product plus nonzero addend in S1, skip S2',
                                      exposed_s2_clocks=PIXELS,
                                      conditional_percent=100*PIXELS/result['rows'][0]['cycles_median'],
                                      not_measured_gain=True))
    args.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print('PASS audited windows, exact retirement count, stores, full-window MLA and representative schedules')


if __name__=='__main__':
    main()
