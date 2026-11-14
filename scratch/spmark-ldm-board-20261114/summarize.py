from pathlib import Path
import json,sys
p=Path(__file__).parent
for name in sys.argv[1:]:
 rows=[json.loads(l) for l in (p/(name+'.jsonl')).read_text().splitlines()]
 snapshots=[x for x in rows if x.get('type')=='snapshot']
 result={'snapshots':len(snapshots),'reader_gaps':sum(x.get('type')=='reader_gap' for x in rows),'generations':sorted(set(x['reset_generation'] for x in snapshots)),'fault_reasons':sorted(set(x['values']['first_fault_reason'] for x in snapshots)),'last':{k:snapshots[-1].get(k) for k in ('clock_hz','reset_generation','save_progress','save_queue','save_errors','panic')} if snapshots else {},'text_tail':''.join(x.get('text','') for x in rows)[-5000:]}
 (p/(name+'.summary.json')).write_text(json.dumps(result,indent=2)+'\n')
 print(name, json.dumps(result)[:900])
