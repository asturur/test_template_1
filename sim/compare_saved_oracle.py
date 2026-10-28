#!/usr/bin/env python3
"""Compare saved CPU traces without repeating firmware execution or delay loops."""
import argparse
import csv
import hashlib
import json
from pathlib import Path

import oracle


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--oracle',type=Path,required=True,help='saved software result.json')
    parser.add_argument('--hdl',type=Path,action='append',required=True,help='HDL bus.tsv; may be repeated')
    args = parser.parse_args()
    result = json.loads(args.oracle.read_text())
    bus = args.oracle.with_name('bus.tsv')
    events = []
    with bus.open() as stream:
        for row in csv.DictReader(stream,delimiter='\t'):
            if row['device'] in oracle.IO_DEVICES:
                select = int(row['byte_enable'],16)
                events.append([row['operation'],int(row['address'],16),select,
                               int(row['data'],16)&oracle.mask(select),row['device']])
    comparisons = [oracle.compare(path,events,result) for path in args.hdl]
    result['comparisons'] = comparisons
    result['saved_comparison'] = dict(firmware_rerun=False,software_bus_sha256=hashlib.sha256(bus.read_bytes()).hexdigest(),
                                     comparator_sha256=hashlib.sha256(Path(oracle.__file__).read_bytes()).hexdigest())
    args.oracle.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(comparisons,indent=2))
    return 0 if all(c['io_events_match'] and c['frontier_matches'] for c in comparisons) else 1


if __name__=='__main__':
    try:
        raise SystemExit(main())
    except (OSError,ValueError,RuntimeError,KeyError) as error:
        raise SystemExit(str(error))
