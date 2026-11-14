import json,re,collections,sys
from pathlib import Path
p=Path(sys.argv[1]);rows=[json.loads(l) for l in p.read_text().splitlines()];buf='';messages=[];epoch=0
for r in rows:
 if r.get('type')=='reader_gap':epoch+=1;buf=''
 if r.get('type')!='text':continue
 for c in bytes.fromhex(r['raw_hex']):
  if c==192:
   if buf:messages.append(buf)
   buf=''
  else:buf+=chr(c)
if buf:messages.append(buf)
snaps=[r for r in rows if r.get('type')=='snapshot'];bitmap=[t for t in messages if t.startswith('C ')];panics=[t for t in messages if 'PANIC' in t]
summary=dict(snapshots=len(snaps),reader_gaps=epoch,bitmap=bitmap,panics=panics,kernel_stop_samples=sum(r['values']['last_pc'] in (0x50324294,0x50324298,0x5032429c) for r in snaps),last_pc=hex(snaps[-1]['values']['last_pc']) if snaps else None,counts=dict(collections.Counter(t for t in bitmap if t.startswith('C SCAN'))))
p.with_suffix('.summary.json').write_text(json.dumps(summary,indent=2)+'\n');print({k:v for k,v in summary.items() if k not in ('bitmap','panics')});print('\n'.join(bitmap[-30:]));print('panics',panics[-5:])
