#!/usr/bin/env python3
"""Record effective selected inputs for any master build, without payload pins."""
import argparse,hashlib,json,os,re,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--source-graph',default='output_files/source-graph.txt');p.add_argument('--output',default='output_files/resident-fit-manifest.json');a=p.parse_args()
root=Path.cwd();sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();inputs={}
for line in Path(a.source_graph).read_text().splitlines():
 if line.startswith('SOURCE '):
  path=Path(line[7:]);path=path.relative_to('/project') if str(path).startswith('/project/') else path.relative_to(root) if path.is_absolute() else path
  inputs[str(path)]=sha(path)
assert inputs
modules={n:[] for n in ['arm920_cache_adapter','arm920_cache_access','arm920_cache_bank','arm920_cache_tags','ngage_bram']}
for name in inputs:
 path=Path(name)
 if path.suffix in ['.sv','.v']:
  text=path.read_text()
  for m in modules:
   if re.search(r'\bmodule\s+'+m+r'\b',text):modules[m].append(name)
assert all(len(x)==1 for x in modules.values()),modules
info=json.loads(Path('output_files/build-info.json').read_text());qsf=Path('Template.qsf').read_text()
assert re.search(r'-name SEED '+str(info['fitter_seed'])+r'\b',qsf)
assert ('ENABLE_DEBUGGER='+str(int(info['enable_debugger']))) in qsf
out=dict(actual_commit=os.getenv('GITHUB_SHA') or subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),seed=info['fitter_seed'],debugger=info['enable_debugger'],effective_qsf=qsf,compiled_source_sha256=inputs,unique_module_definitions=modules,production_bram_sha256=sha(Path('rtl/ngage_bram.v')),physical_pll_sha256=sha(Path('rtl/pll/pll_0002.v')))
Path(a.output).write_text(json.dumps(out,indent=2)+'\n');print('PASS effective master input manifest',out['actual_commit'],len(inputs),'sources')
