"""Slice the accepted native input-decode interval; no hardware access."""
from pathlib import Path
import json,collections,hashlib
ROOT=Path(__file__).resolve().parents[3]
P=ROOT/'build/sim/jpeg-profile'
P.mkdir(parents=True,exist_ok=True)
N=ROOT/'tests/cpu/jpeg_observer/local'
matched=json.loads((N/'confirmed-ordering.json').read_text())['events']
rows=[json.loads(line) for line in (N/'observed-tests-01.jsonl').read_text().splitlines()]
start=next(i for i,x in enumerate(rows) if x.get('type')=='text' and x.get('sequence')==matched[0]['sequence'])
end=next(i for i,x in enumerate(rows) if x.get('type')=='text' and x.get('sequence')==matched[-1]['sequence'])
assert start<end
samples=[x for x in rows[start:end] if x.get('type')=='snapshot']
mods=json.loads((N/'rom-modules.json').read_text());counts=collections.Counter()
for sample in samples:
 pc=sample['values']['last_pc']
 counts['/'.join(m['name'] for m in mods if m['base']<=pc<m['end']) or 'kernel/other']+=1
(P/'request-samples.json').write_text(json.dumps(samples,indent=2)+'\n')
print(json.dumps(dict(samples=len(samples),modules=dict(counts),source_sha256=hashlib.sha256((N/'observed-tests-01.jsonl').read_bytes()).hexdigest()),indent=2))
