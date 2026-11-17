#!/usr/bin/env python3
"""Offline candidate selection for lifecycle/port regressions; never edits RTL."""
import argparse, hashlib, json, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
p=argparse.ArgumentParser();p.add_argument('out');p.add_argument('--fixture',default='qualification');p.add_argument('--old',action='store_true');p.add_argument('--arg',default='');p.add_argument('--negative',action='store_true');a=p.parse_args()
out=ROOT/a.out;out.mkdir(parents=True,exist_ok=False)
overlay=ROOT/('tests/cpu/cache_resident_qualification/rtl' if a.old else 'tests/cpu/cache_probe_retime/rtl')
src=[ROOT/'rtl/ngage_bram.v',*sorted((ROOT/'rtl/arm920').glob('*.sv'))]
src=[overlay/s.name if (overlay/s.name).exists() else s for s in src]
if a.negative:
 original=overlay/'cache_access.sv';bad=out/'negative-cache-access.sv'
 text=original.read_text();assert text.count('probe_result_tag <= probe_owner_tag;')==1
 bad.write_text(text.replace('probe_result_tag <= probe_owner_tag;', 'probe_result_tag <= req_mva[31:5];'))
 src=[bad if s.name=='cache_access.sv' else s for s in src]
if a.fixture in ['qualification','first_failure']:
 tb=(ROOT/('tests/cpu/cache_resident_qualification/test.v' if a.fixture=='qualification' else 'tests/cpu/cache_resident_qualification/first_failure.v')).read_text()
else:
 tbpath=ROOT/f'tests/cpu/{"cache_probe" if a.fixture in ["adapter_lock","schedule"] else a.fixture}'/('test.sv' if a.fixture in ['cache_refill','cache_maintenance'] else 'test.v')
 tb=tbpath.read_text()
 if a.fixture=='cache_admit_probe' and not a.old:
  tb=tb.replace('module test;', 'module test;\n reg [26:0] bad_tag; reg [5:0] bad_way;')
  tb=tb.replace("dut.cache.probe_owner_tag = dut.cache.probe_owner_tag ^ 27'h8;", "bad_tag=dut.cache.probe_owner_tag ^ 27'h8; force dut.cache.probe_owner_tag=bad_tag;")
  tb=tb.replace("dut.cache.probe_owner_way = dut.cache.probe_owner_way ^ 6'd1;", "bad_way=dut.cache.probe_owner_way ^ 6'd1; force dut.cache.probe_owner_way=bad_way;")
  tb=tb.replace('    // A valid tag with', '    release dut.cache.probe_owner_tag;\n    // A valid tag with')
  tb=tb.replace('    // Same-slot stores,', '    release dut.cache.probe_owner_way;\n    // Same-slot stores,')
 if a.fixture=='schedule':
  tb=tb.replace(".fast_enable(1'b1)",'.fast_enable(fast_enable)')
  start=tb.index('  initial begin\n    for (j = 0;')
  end=tb.index('  initial begin',start+15)
  tb=tb[:start]+"  initial begin\n    for(j=0;j<32768;j=j+1)mem[j]=32'h51000000^(j*4);\n    repeat(4)tick();reset=0;tick();schedule_cases();$finish;\n  end\n"+tb[end:]
  tb=tb.replace('endmodule','`include "tests/cpu/cache_probe_retime/schedule.vh"\nendmodule')
 if a.fixture=='adapter_lock':
  tb=tb.replace('    $display(\n        \"PASS:', '    pending_adapter_lock();\n    $display(\n        \"PASS:')
  tb=tb.replace('endmodule','`include \"tests/cpu/cache_resident_qualification/adapter_extra.vh\"\nendmodule')
 # Access+bank+tags from candidate, not just a substituted controller.
 # Added indexed_mva is irrelevant in old fixtures with indexed_store tied low.
 if a.fixture in ['cache_refill','cache_maintenance']:
  tb=tb.replace('.indexed_store(1\'b0),', '.indexed_store(1\'b0),\n      .indexed_mva(32\'b0),')
(out/'test.v').write_text(tb);src.append(out/'test.v')
files=[*src,Path(__file__).resolve(),ROOT/'tests/cpu/cache_resident_qualification/test.v']
if a.fixture=='schedule':files.append(ROOT/'tests/cpu/cache_probe_retime/schedule.vh')
if a.fixture=='adapter_lock':files.append(ROOT/'tests/cpu/cache_resident_qualification/adapter_extra.vh')
sha=lambda s:hashlib.sha256(s.read_bytes()).hexdigest()
hashes={str(s.relative_to(ROOT)):sha(s) for s in files}
docker=['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',f'{ROOT}:/work','-w','/work','--entrypoint']
identity={'revision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'compiled_sources':[str(s.relative_to(ROOT)) for s in src],'sha256':hashes,'fixture':a.fixture,'old':a.old,'arg':a.arg,'image':subprocess.check_output(['docker','image','inspect','jotego/simulator:arm64','--format','{{.Id}}'],text=True).strip()}
(out/'source.json').write_text(json.dumps(identity,indent=2)+'\n')
def call(cmd,log):
 with (out/log).open('w') as f:return subprocess.run(cmd,cwd=ROOT,stdout=f,stderr=subprocess.STDOUT).returncode
if call(docker+['verilator','jotego/simulator:arm64','--binary','-j','3','--timing','--assert','-Wno-fatal','-Wno-lint','--top-module','test','--Mdir',a.out,*identity['compiled_sources']],'build.log'):raise SystemExit('build failed '+str(out/'build.log'))
rc=call(docker+[f'/work/{a.out}/Vtest','jotego/simulator:arm64']+([a.arg] if a.arg else []),'run.log')
repeat_sha=None
if rc==0 and a.fixture=='qualification':
 repeat_rc=call(docker+[f'/work/{a.out}/Vtest','jotego/simulator:arm64']+([a.arg] if a.arg else []),'repeat.log')
 prefixes=('EDGE ','CASE ','PASS','FAST_CONSUMERS','STALE_FAST')
 events=lambda p:[s for s in p.read_text().splitlines() if s.startswith(prefixes)]
 assert repeat_rc==0 and events(out/'run.log')==events(out/'repeat.log'),'qualification repeat differs'
 repeat_sha=sha(out/'repeat.log')
assert hashes=={str(s.relative_to(ROOT)):sha(s) for s in files},'source changed during run'
(out/'result.json').write_text(json.dumps({'exit_code':rc,'repeat_sha256':repeat_sha,'source':identity,'log_sha256':sha(out/'run.log')},indent=2)+'\n')
print((out/'run.log').read_text()[-2500:]);raise SystemExit(0 if rc==0 else 1)
