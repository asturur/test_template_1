#!/usr/bin/env python3
"""Record effective selected inputs for the current phone build."""
import argparse,hashlib,json,os,re,subprocess
from decimal import Decimal
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--source-graph',default='output_files/source-graph.txt');p.add_argument('--output',default='output_files/resident-fit-manifest.json');a=p.parse_args()
root=Path.cwd();sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();inputs={}
for line in Path(a.source_graph).read_text().splitlines():
 if line.startswith('SOURCE '):
  path=Path(line[7:]);path=path.relative_to('/project') if str(path).startswith('/project/') else path.relative_to(root) if path.is_absolute() else path
  inputs[str(path)]=sha(path)
assert inputs
if 'rtl/arm9v2/arm925t_phone.v' in inputs:
 names=['ngage2_arm925t','ngage2_arm9v2_core','ngage2_zap_top','ngage2_zap_cache','ngage2_zap_dcache','ngage2_zap_tlb']
else:
 names=['arm920_cache_adapter','arm920_cache_access','arm920_cache_bank','arm920_cache_tags']
modules={name:[] for name in [*names,'ngage_bram']}
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

board = Path('Template.sv').read_text()
pll = Path('rtl/pll/pll_0002.v').read_text()
system_hz, = re.findall(r'localparam\s+integer\s+SYS_CLK_HZ\s*=\s*(\d+)\s*;', board)
clock0, = re.findall(r'\.output_clock_frequency0\s*\(\s*"([\d.]+) MHz"\s*\)', pll)
if Decimal(clock0) * 1_000_000 != int(system_hz) or int(system_hz) not in (78_000_000, 104_000_000):
    raise ValueError('PLL output 0 and board system clock disagree or use an unsupported rate')
out['physical_cpu_mhz'] = int(system_hz) // 1_000_000
info['physical_cpu_mhz'] = out['physical_cpu_mhz']
Path('output_files/build-info.json').write_text(json.dumps(info, indent=2) + '\n')
Path(a.output).write_text(json.dumps(out,indent=2)+'\n');print('PASS effective phone input manifest',out['actual_commit'],len(inputs),'sources')
