#!/usr/bin/env python3
"""Record effective CI project inputs after seed/debug selection, before fit."""
from pathlib import Path
import hashlib,json,re,subprocess,argparse
parser=argparse.ArgumentParser();parser.add_argument("--actual-commit");parser.add_argument("--source-graph",default="output_files/source-graph.txt");parser.add_argument("--output",default="output_files/resident-fit-manifest.json");args=parser.parse_args()
root=Path.cwd()
expected=json.loads(Path('tools/resident_store_fit/expected.json').read_text())
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
for p,h in expected['payloads'].items():assert sha(p)==h,(p,sha(p),h)
lines=Path(args.source_graph).read_text().splitlines()
inputs={}
for s in lines:
 if s.startswith('SOURCE '):
  p=Path(s[7:]);p=p.relative_to('/project') if str(p).startswith('/project/') else p.relative_to(root) if p.is_absolute() else p
  inputs[str(p)]=sha(p)
for p in expected['payloads']:assert p in inputs,p
assert sha('rtl/ngage_bram.v')==expected['production_bram_sha256']
modules={n:[] for n in ['arm920_cache_access','arm920_cache_bank','arm920_cache_tags','ngage_bram']}
for p in inputs:
 if Path(p).suffix not in ['.sv','.v']:continue
 s=Path(p).read_text(errors='replace')
 for m in modules:
  if re.search(r'\bmodule\s+'+m+r'\b',s):modules[m].append(p)
assert all(len(v)==1 for v in modules.values()),modules
qsf=Path('Template.qsf').read_text()
assert re.search(r'-name SEED 42\b',qsf)
assert 'ENABLE_DEBUGGER=1' in qsf
assert Path('rtl/pll/pll_0002.v').read_text().count('78.000000 MHz')==2
out={**expected,'actual_commit':args.actual_commit or subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'effective_qsf':qsf,'compiled_source_sha256':inputs,'unique_module_definitions':modules}
Path(args.output).write_text(json.dumps(out,indent=2)+'\n')
print('PASS isolated fit manifest',out['actual_commit'],len(inputs),'source files')
