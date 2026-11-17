#!/usr/bin/env python3
"""Reject a deliberately wrong expected physical byte, reusing a verified build."""
from pathlib import Path
import argparse,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[3]
p=argparse.ArgumentParser();p.add_argument('run',type=Path);a=p.parse_args()
run=ROOT/a.run;manifest=json.loads((run/'manifest.json').read_text());symbols=manifest['symbols']
exe=run/'obj/Vbench';assert hashlib.sha256(exe.read_bytes()).hexdigest()==manifest['executable_sha256']
cp=lambda p:'/work/'+str(p.relative_to(ROOT))
args=['+program='+cp(run/'program.hex'),'+payload='+cp(run/'empty.hex'),'+firmware='+cp(run/'empty.hex')]
for arg,name in [('begin_pc','body_begin'),('end_pc','body_end'),('stores_begin','stores_begin'),('stores_end','stores_end'),('irq_marker','irq_marker'),('forbidden_fault','forbidden_fault_store'),('forbidden_irq','forbidden_irq_store')]:args.append(f'+{arg}={symbols[name]:x}')
log=run/'wrong-physical-byte.log';assert not log.exists()
with log.open('w') as f:
 result=subprocess.run(['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',str(ROOT)+':/work','-w','/work','--entrypoint',cp(exe),'jotego/simulator:arm64',*args,'+corrupt_oracle=1'],cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
text=log.read_text()
assert result.returncode!=0 and 'physical cache mutation order/slot/word/bytes mismatch seq=0' in text
assert 'PASS overlap' not in text
(run/'wrong-physical-byte.json').write_text(json.dumps(dict(status='EXPECTED_FAILURE',returncode=result.returncode,log_sha256=hashlib.sha256(log.read_bytes()).hexdigest(),reason='deliberately wrong first expected physical byte rejected'),indent=2)+'\n')
print('PASS wrong physical-byte control rejected at first actual RAM mutation')
