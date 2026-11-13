from pathlib import Path
import bisect,collections,hashlib,json,re,struct,sys
path=Path(sys.argv[1]);events=[json.loads(l) for l in path.read_text().splitlines()];snapshots=[e for e in events if e['type']=='snapshot'];text='';offsets=[];chunks=[]
for e in events:
 if e['type']=='text':offsets.append(len(text));chunks.append(e);text+=e['text']
records=[]
for m in re.finditer(r'R[1-8] [^\n]*|A NOS [^\n]*|M TESTS [^\n]*|A RESULTS [^\n]*|Y SIM [^\n]*|D EVENT id=[0-9a-f]{8} value=[0-9a-f]{8}',text):
 e=chunks[bisect.bisect_right(offsets,m.start())-1];records.append(dict(cycle=e['cycle'],sequence=e['sequence'],text=m.group()))
summary=dict(capture=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),events=dict(collections.Counter(e['type'] for e in events)),snapshots=len(snapshots),reset_generations=sorted({e['reset_generation'] for e in snapshots}),panic_masks=sorted({e['panic']['valid_mask'] for e in snapshots}),first_fault_reasons=sorted({e['values']['first_fault_reason'] for e in snapshots}),queue_fault=any(e.get('save_queue',{}).get('fault',False) for e in snapshots),producer_drops=[e for e in events if e['type']=='producer_drops'],native_events=records)
rfs=[e for e in records if e['text'].startswith('R4 ')];replies=[e for e in records if e['text'].startswith('R3 0000f1a1 ')];arrays=[e for e in records if e['text'].startswith(('M TESTS ','A RESULTS '))]
if rfs and replies:
 delta=(replies[0]['cycle']-rfs[0]['cycle'])&0xffffffff;assert delta<0x80000000
 summary.update(rf_receiver_observed=True,request_to_receiver_cycles=delta,request_to_receiver_seconds=delta/snapshots[0]['clock_hz'])
if arrays:
 m=re.match(r'(?:M TESTS|A RESULTS) ((?:[0-9a-f]{8} ){6})',arrays[-1]['text']);assert m;data=b''.join(int(w,16).to_bytes(4,'little') for w in m[1].split());rom=Path('firmware/THC N-Gage ROM Dump/ngage-gsmstuff-0x5149D280.dll').read_bytes();assert hashlib.sha256(rom).hexdigest()=='e5870e918c90d9c7a6403eb0ee305d174e906aeae0a7fa8069e85a18aeec7aa1';b=rom[96:]
 for index,id in ((14,0x15),(16,2),(20,0x1e),(22,0x36)):assert b[0x516f785c-0x5149d280+index*16+10]==id
 summary.update(native_result_bytes=data.hex(),rf_test_1e=data[20],adsp_test_36=data[22],bt_test_15=data[14],current_test_02=data[16])
path.with_suffix('.txt').write_text(text);path.with_suffix('.summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps({k:v for k,v in summary.items() if k!='native_events'},indent=2))
