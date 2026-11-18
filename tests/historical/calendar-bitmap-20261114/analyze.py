import json,re,collections
from pathlib import Path
import sys
p=Path(sys.argv[1]);rows=[json.loads(l) for l in p.read_text().splitlines()];buf='';messages=[];epoch=0;first=None;clock=0;last=None;start=end=0;se=0
for r in rows:
 if r.get('type')=='reader_gap':epoch+=1
 if r.get('type')!='text':continue
 if last is not None:clock+=(r['cycle']-last)&0xffffffff
 last=r['cycle']
 for c in bytes.fromhex(r['raw_hex']):
  if c==192:
   if buf:messages.append(dict(text=buf,start=start,end=end,se=se,ee=epoch))
   buf=''
  else:
   if not buf:start=clock;se=epoch
   buf+=chr(c);end=clock
if buf and re.fullmatch(r'L (?:WINDOW start=[0-9a-f]{8} end=[0-9a-f]{8} caller=[0-9a-f]{8}|HEADER(?:12|16) bytes=[0-9a-f]{8} caller=[0-9a-f]{8} sample25=[0-9a-f]{8}|LINE row=[0-9a-f]{8} mode=[0-9a-f]{8} sample25=[0-9a-f]{8})',buf):messages.append(dict(text=buf,start=start,end=end,se=se,ee=epoch,complete_fixed_fields_at_eof=True))
if buf and re.fullmatch(r'G (?:PIXEL|SCAN|STRETCH) bitmap=[0-9a-f]{8} width=[0-9a-f]{8} height=[0-9a-f]{8} depth=[0-9a-f]{8} colour=[0-9a-f]{8} compression=[0-9a-f]{8} x=[0-9a-f]{8} y=[0-9a-f]{8} arg3=[0-9a-f]{8} caller=[0-9a-f]{8}(?: data=[0-9a-f]{8})?',buf):messages.append(dict(text=buf,start=start,end=end,se=se,ee=epoch,complete_fixed_fields_at_eof=True))
lcd=[m for m in messages if m['text'].startswith(('L ','G '))];snaps=[r for r in rows if r.get('type')=='snapshot'];r=dict(path=str(p),reader_gaps=epoch,snapshots=len(snaps),lcd=lcd,counts=dict(collections.Counter(m['text'].split()[1] for m in lcd)),panics=[m for m in messages if m['text'].startswith(('X PANIC','X THREAD_PANIC'))],abort_loop_snapshots=sum((r['values']['cpsr']&31)==0x17 and r['values']['last_pc'] in (0x50324294,0x50324298,0x5032429c) for r in snaps),mode_counts=dict(collections.Counter(hex(r['values']['cpsr']&31) for r in snaps)))
p.with_suffix('.summary.json').write_text(json.dumps(r,indent=2)+'\n');print('snapshots',len(snaps),'gaps',epoch,'counts',r['counts'],'panics',len(r['panics']),'abort_loop_samples',r['abort_loop_snapshots'])
for m in lcd[-35:]:print(round(m['start']/78e6,3),m['se'],m['text'])
