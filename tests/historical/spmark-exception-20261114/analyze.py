from pathlib import Path
import json,re,sys
p=Path(__file__).parent;name=sys.argv[1] if len(sys.argv)>1 else 'boot';rs=[json.loads(l) for l in (p/(name+'.jsonl')).read_text().splitlines()];t=''.join(r.get('text','') for r in rs if r['type']=='text');(p/(name+'.txt')).write_text(t);ss=[r for r in rs if r['type']=='snapshot'];msgs=[x.strip() for x in re.split('[\ufffd\xc0\r\n]+',t) if x.startswith(('S LOAD','S DLL','S LOOK','S CMP0','S FATAL','S CP15','S STACK','S FILL','X PANIC','X THREAD_PANIC'))];fatal=[]
for m in msgs:
 if m.startswith('S FATAL '):
  v=[int(x,16) for x in m.split()[2:]]
  if len(v)!=21:raise ValueError('incomplete fatal frame')
  fatal.append(dict(kind=v[0],pc=hex(v[1]),cpsr=hex(v[2]),detail_pc=hex(v[3]),far=hex(v[4]),fsr=hex(v[5]),registers={f'r{i}':hex(x) for i,x in enumerate(v[6:19])},sp=hex(v[19]),lr=hex(v[20])))
contexts=[]
for m in msgs:
 if m.startswith('S CP15 '):
  v=[int(x,16) for x in m.split()[2:]];contexts.append(dict(pid=hex(v[0]),ttbr=hex(v[1]),domain=hex(v[2])))
stacks=[]
for m in msgs:
 if m.startswith('S STACK '):
  v=[int(x,16) for x in m.split()[2:]];stacks.append(dict(sp=hex(v[0]),words=[hex(x) for x in v[1:]]))
r=dict(contexts=contexts,stacks=stacks,samples=len(ss),generations=sorted(set(x['reset_generation'] for x in ss)),faults=sorted(set(x['values']['first_fault_reason'] for x in ss)),reader_gaps=sum(x['type']=='reader_gap' for x in rs),messages=msgs,fatal=fatal);(p/(name+'.summary.json')).write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))
