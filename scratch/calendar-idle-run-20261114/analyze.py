import json,re,collections,sys
from pathlib import Path
p=Path(sys.argv[1]);rows=[json.loads(l) for l in p.read_text().splitlines()];buf='';events=[];epoch=0;seq=cycle=0;start_seq=0
pattern=r'I (START|RUN|READY) object=([0-9a-f]{8}) (?:callback|status)=([0-9a-f]{8}) (?:param|priority)=([0-9a-f]{8})'
def flush():
 m=re.fullmatch(pattern,buf)
 if not m:return
 kind,obj,a,b=m.groups();e=dict(kind=kind,object=obj,epoch=epoch,sequence=start_seq,end_sequence=seq,cycle=cycle,text=buf)
 if kind=='READY':e.update(status=int(a,16),priority=int(b,16)-(0x100000000 if int(b,16)&0x80000000 else 0))
 else:e.update(callback=a,param=b)
 events.append(e)
for r in rows:
 if r.get('type')=='reader_gap':buf='';epoch+=1
 if r.get('type')!='text':continue
 seq=r['sequence'];cycle=r['cycle']
 for c in bytes.fromhex(r['raw_hex']):
  if c==192:
   if buf:flush()
   buf='';start_seq=seq
  else:buf+=chr(c)
if buf:flush()
pending={};pairs=[]
for e in events:
 key=(e['epoch'],e['object'])
 if e['kind']=='READY':pending[key]=e
 elif e['kind']=='RUN' and key in pending:pairs.append(dict(ready=pending.pop(key),run=e))
snaps=[r for r in rows if r.get('type')=='snapshot'];out=dict(snapshots=len(snaps),reader_gaps=epoch,kernel_stop_samples=sum(r['values']['last_pc'] in (0x50324294,0x50324298,0x5032429c) for r in snaps),events=events,ready_run_pairs=pairs,unpaired_ready=list(pending.values()))
p.with_suffix('.summary.json').write_text(json.dumps(out,indent=2)+'\n');print({k:v for k,v in out.items() if k not in ('events','ready_run_pairs','unpaired_ready')});print('counts',dict(collections.Counter(e['kind'] for e in events)));print('unpaired_ready',out['unpaired_ready']);print('\n'.join(e['text'] for e in events[-40:]))
