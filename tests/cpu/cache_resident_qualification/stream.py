#!/usr/bin/env python3
"""Explicit source overlay; original five-stream checker/golden model unchanged."""
import argparse, hashlib, importlib.util, json, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
p=argparse.ArgumentParser();p.add_argument('out');p.add_argument('--data-probe',type=int,choices=[0,1],default=0);p.add_argument('--line-refill',type=int,choices=[0,1],default=0);p.add_argument('--baseline',action='store_true');args=p.parse_args()
out=ROOT/args.out
out.mkdir(parents=True,exist_ok=False)
def call(cmd,log):
    with (out/log).open('w') as f:
        return subprocess.run(cmd,cwd=ROOT,stdout=f,stderr=subprocess.STDOUT).returncode
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
docker=['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',f'{ROOT}:/work','-w','/work','--entrypoint']
overlay=ROOT/'tests/cpu/cache_resident_qualification/rtl'
sources=[ROOT/'rtl/ngage_bram.v',*sorted((ROOT/'rtl/arm920').glob('*.sv'))]
if not args.baseline:sources=[overlay/s.name if (overlay/s.name).exists() else s for s in sources]
tb=(ROOT/'tests/cpu/cache_resident_stream/test.v').read_text().replace('arm920_cache_access dut (',f'arm920_cache_access #(.DATA_PROBE({args.data_probe}), .LINE_REFILL({args.line_refill})) dut (')
tb=tb.replace(".line_reject(1'b0)", ".line_reject(1'b1)").replace(".line_ready(1'b0)", ".line_ready(1'b1)") if args.line_refill else tb
# Optional extra directed suite shares the independent actual-RAM scoreboard.
if not args.baseline:
    tb=tb.replace('                    #1;', '                    #1;\n                    if (stream==5) $display("DIRECTED_DIRTY edge=%0d id=%0d slot=%0d actual=%b",edge_id,nc-1,obs_sample_slot,obs_stored_dirty);')
    tb=tb.replace('        $display("PASS: five', '        directed();\n        $display("PASS: five')
    tb=tb.replace('    initial begin #2000000;', '    `include "tests/cpu/cache_resident_pipeline/directed.vh"\n    initial begin #2000000;')
(out/'test.v').write_text(tb)
sources.append(out/'test.v')
files=[ROOT/'tests/cpu/cache_resident_stream/test.v',ROOT/'tests/cpu/cache_resident_stream/report.py',*sources,ROOT/'tests/cpu/cache_resident_stream/observe.vh',Path(__file__).resolve()]
if not args.baseline:files.append(ROOT/'tests/cpu/cache_resident_pipeline/directed.vh')
hashes={str(s.relative_to(ROOT)):sha(s) for s in files}
manifest={'image':subprocess.check_output(['docker','image','inspect','jotego/simulator:arm64','--format','{{.Id}}'],text=True).strip(),'revision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'mode':'baseline' if args.baseline else 'candidate','DATA_PROBE':args.data_probe,'LINE_REFILL':args.line_refill,'READ_ONLY':0,'mixed_port_collision':'poison all ones' if not args.baseline else 'production model','compiled_sources':[str(s.relative_to(ROOT)) for s in sources],'sha256':hashes}
(out/'source.json').write_text(json.dumps(manifest,indent=2)+'\n')
cmd=docker+['verilator','jotego/simulator:arm64','--binary','-j','4','--timing','--assert','-Wno-fatal','-Wno-lint','--top-module','test','--Mdir',args.out,*manifest['compiled_sources']]
if call(cmd,'build.log'):raise SystemExit('Build failed: '+str(out/'build.log'))
for name in ['normal','repeat','negative']:
    rc=call(docker+[f'/work/{args.out}/Vtest','jotego/simulator:arm64']+(['+corrupt_expected'] if name=='negative' else []),name+'.log')
    text=(out/(name+'.log')).read_text()
    if name=='negative':
        assert rc and 'checker byte mismatch (negative control=1)' in text
    else:assert rc==0 and 'PASS: five' in text, str(out/(name+'.log'))
assert hashes=={str(s.relative_to(ROOT)):sha(s) for s in files},'Source changed'
spec=importlib.util.spec_from_file_location('base_report',ROOT/'tests/cpu/cache_resident_stream/report.py');r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)
r.source_hashes=lambda:hashes
r.report(out)
result=json.loads((out/'result.json').read_text())
if not args.baseline:
    for stream in result['streams']:
        assert stream['accept_intervals']=={'1':255} and stream['commit_intervals']=={'1':255}
assert [s for s in (out/'normal.log').read_text().splitlines() if s.startswith('DIRECTED')] == [s for s in (out/'repeat.log').read_text().splitlines() if s.startswith('DIRECTED')]
result['directed']=[s for s in (out/'normal.log').read_text().splitlines() if s.startswith('DIRECTED')]
(out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
for s in result['streams']:print(s['name'],s['first_accept'],s['last_accept'],s['first_commit'],s['last_commit'],s['accept_intervals'],s['commit_intervals'])
print('PASS: checks/repeat/negative',args.out)
