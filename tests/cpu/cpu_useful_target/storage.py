#!/usr/bin/env python3
"""Compact only the completed Step5H runs; preserve journals and provenance."""
from pathlib import Path
import gzip
import hashlib
import json
import shutil

ROOT=Path(__file__).resolve().parents[3]
RUNS=['spmark-payload/useful-target-5f-arm-01',
      'spmark-payload/useful-target-5f-arm-02',
      'jpeg-payload/useful-target-5f-jpeg-01']
sha=lambda b:hashlib.sha256(b).hexdigest()

for name in RUNS:
    p=ROOT/'build/sim'/name
    if (p/'storage.json').exists():
        continue
    result=json.loads((p/'result.json').read_text())
    if name.endswith('arm-01'):
        assert result['status']=='INCOMPLETE'
        assert 'late store actual RAM order/address/mask/data' in (p/'fill8_tail-0-0-0.log').read_text()
        assert (p/'fill8_tail-0-0-0.log').read_text().rstrip().endswith('Aborting...')
    else:
        assert result['status']=='PASS'
    manifest=json.loads((p/'manifest.json').read_text())
    ledger=dict(run=name,completed_status=result['status'],
                manifest_sha256=sha((p/'manifest.json').read_bytes()),
                retired_artifacts={},logs={},removed_generated=[])
    exe=p/'obj/Vbench'
    ledger['retired_artifacts']['obj/Vbench']=dict(sha256=sha(exe.read_bytes()),bytes=exe.stat().st_size)
    for log in p.glob('*.log'):
        raw=log.read_bytes()
        gz=log.with_suffix('.log.gz')
        assert not gz.exists()
        gz.write_bytes(gzip.compress(raw,compresslevel=9,mtime=0))
        assert gzip.decompress(gz.read_bytes())==raw
        ledger['logs'][log.name]=dict(raw_sha256=sha(raw),bytes=len(raw),archive_sha256=sha(gz.read_bytes()))
        log.unlink()
    # Source inputs are reproducible from the pinned Git object; fixture
    # observer snapshots, manifest hashes and original guest assembly remain.
    for dirname in ['obj','source']:
        directory=p/dirname
        assert directory.is_dir()
        ledger['removed_generated'].append(dirname)
        shutil.rmtree(directory)
    for suffix in ['*.o','*.elf','*.bin','*.hex']:
        for f in p.glob(suffix):
            ledger['removed_generated'].append(f.name)
            f.unlink()
    (p/'storage.json').write_text(json.dumps(ledger,indent=2)+'\n')
    print('Compacted',name)
