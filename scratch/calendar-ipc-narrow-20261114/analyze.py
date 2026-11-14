import json,re,collections
from pathlib import Path
p=Path('scratch/calendar-ipc-narrow-20261114');rows=[json.loads(l) for l in (p/'calendar.jsonl').read_text().splitlines()];messages=[];buf='';clock=0;last=None;epoch=0;start=0;se=0;finish=0
for r in rows:
 if r.get('type')=='reader_gap':epoch+=1
 if r.get('type')!='text':continue
 if last is not None:clock+=(r['cycle']-last)&0xffffffff
 last=r['cycle']
 for c in bytes.fromhex(r['raw_hex']):
  if c==192:
   if buf:messages.append(dict(text=buf,start=start,end=finish,se=se,ee=epoch))
   buf=''
  else:
   if not buf:start=clock;se=epoch
   buf+=chr(c);finish=clock
pairs=[];beg=re.compile(r'K BEGIN ipc=([0-9a-f]{8}) handle=([0-9a-f]{8}) caller=([0-9a-f]{8})');end=re.compile(r'K END ipc=([0-9a-f]{8}) handle=([0-9a-f]{8}) rc=([0-9a-f]{8})')
for a,b in zip(messages,messages[1:]):
 x=beg.fullmatch(a['text']);y=end.fullmatch(b['text'])
 if x and y and x.groups()[:2]==y.groups()[:2] and a['se']==a['ee']==b['se']==b['ee']:
  pairs.append(dict(ipc=x[1],handle=x[2],caller=x[3],rc=y[3],seconds=(b['start']-a['end'])/78e6))
r=dict(reader_gaps=epoch,pairs=pairs,method='Only consecutive complete matching BEGIN/END in one gap-free epoch; debug execution cost remains',messages=[m for m in messages if m['text'].startswith('K ')])
(p/'measurements.json').write_text(json.dumps(r,indent=2)+'\n');print('gaps',epoch,'pairs',len(pairs));print(json.dumps(sorted(pairs,key=lambda x:x['seconds'],reverse=True)[:6],indent=2))
