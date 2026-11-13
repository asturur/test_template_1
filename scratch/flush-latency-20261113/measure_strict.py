import collections,json,re
from pathlib import Path
root=Path('scratch/flush-latency-20261113');rows=[]
for line in (root/'phone-running.jsonl').read_text().splitlines():
 try:rows.append(json.loads(line))
 except ValueError:pass
messages=[];buf='';start=end=0;clock=0;last=None;epoch=0;start_epoch=0
for r in rows:
 if r.get('type')=='reader_gap':epoch+=1
 if r.get('type')!='text':continue
 if last is not None:clock+=(r['cycle']-last)&0xffffffff
 last=r['cycle']
 for c in bytes.fromhex(r['raw_hex']):
  if c==0xc0:
   if buf:messages.append(dict(text=buf,start=start,end=end,start_epoch=start_epoch,end_epoch=epoch))
   buf=''
  else:
   if not buf:start=clock;start_epoch=epoch
   buf+=chr(c);end=clock
if buf:messages.append(dict(text=buf,start=start,end=end,start_epoch=start_epoch,end_epoch=epoch))
bpat=re.compile(r'Q BEGIN op=([0-9a-f]{8}) file=([0-9a-f]{8}) handle=([0-9a-f]{8}) offset=([0-9a-f]{8}) bytes=([0-9a-f]{8}) caller=([0-9a-f]{8}) thread=Phone\[100058b3\]0003::Phone')
epat=re.compile(r'Q END op=([0-9a-f]{8}) file=([0-9a-f]{8}) rc=([0-9a-f]{8})')
pairs=[]
for i,b in enumerate(messages[:-1]):
 begin=bpat.fullmatch(b['text']);e=messages[i+1];end=epat.fullmatch(e['text'])
 if begin and end and begin.groups()[:2]==end.groups()[:2] and b['start_epoch']==b['end_epoch']==e['start_epoch']==e['end_epoch']:
  pairs.append(dict(op=begin[1],file=begin[2],handle=begin[3],offset=int(begin[4],16),bytes=int(begin[5],16),rc=end[3],seconds=(e['start']-b['end'])/78e6,start=b['start'],end=e['end']))
paths=[m['text'] for m in messages if m['text'].startswith('Q PATH')]
phone=[m for m in messages if 'thread=Phone[' in m['text']]
panics=[m for m in messages if 'X VIEW_TARGET' in m['text'] or ('X THREAD_PANIC' in m['text'] and 'a2=0000000b' in m['text'])]
report=dict(method='Only complete consecutive BEGIN+END messages within one gap-free epoch; no FIFO pairing across corruption',reader_gaps=epoch,pairs=pairs,paths=paths,panics=panics,valid_begins=sum(bool(bpat.fullmatch(m['text'])) for m in messages),valid_ends=sum(bool(epat.fullmatch(m['text'])) for m in messages),phone_io_span_seconds=(phone[-1]['end']-phone[0]['start'])/78e6 if phone else None)
(root/'strict-measurements.json').write_text(json.dumps(report,indent=2)+'\n')
print('strict pairs',len(pairs),'valid begins',report['valid_begins'],'valid ends',report['valid_ends'],'Phone I/O span',report['phone_io_span_seconds'])
for op in sorted(set(e['op'] for e in pairs)):
 a=[e for e in pairs if e['op']==op];print(op,'count',len(a),'sum seconds',sum(e['seconds'] for e in a),'max',max(e['seconds'] for e in a),'errors',sum(e['rc']!='00000000' for e in a))
print('paths',paths)
for m in panics:print('panic at',m['start']/78e6,m['text'])
