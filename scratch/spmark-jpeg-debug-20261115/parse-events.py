from pathlib import Path
import json,re,sys
for filename in sys.argv[1:]:
 rows=[]
 for l in Path(filename).read_text().splitlines():
  try:rows.append(json.loads(l))
  except json.JSONDecodeError:pass
 text='';spans=[];epoch=0
 for r in rows:
  if r.get('type')=='reader_gap':
   text+='\n<READER_GAP>\n';epoch+=1
  if r.get('type')!='text':continue
  if r.get('dropped',0):epoch+=1
  r=dict(r,reader_epoch=epoch)
  b=bytes.fromhex(r.get('raw_hex','')).decode('latin1');spans.append((len(text),len(text)+len(b),r));text+=b
 found=[]
 for m in re.finditer(r'J (AFTER|CANCEL|CLOSE|STOP) obj=([0-9a-fA-F]{8}) value=([0-9a-fA-F]{8}) caller=([0-9a-fA-F]{8})',text):
  r=next(x for a,b,x in spans if a<=m.start()<b)
  found.append(dict(event=m[1],obj=int(m[2],16),value=int(m[3],16),caller=int(m[4],16),cycle=r['cycle'],generation=r['generation'],sequence=r['sequence'],reader_epoch=r['reader_epoch']))
 out=Path(filename).with_suffix('.events.json');out.write_text(json.dumps(found,indent=2)+'\n')
 print(Path(filename).name,len(found),'events')
 for x in found:print(x['event'],hex(x['obj']),hex(x['value']),hex(x['caller']),'cycle',x['cycle'],'gen',x['generation'])
