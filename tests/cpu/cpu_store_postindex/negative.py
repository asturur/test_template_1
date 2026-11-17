#!/usr/bin/env python3
"""Deliberately wrong independent physical-byte oracles, immutable executable."""
from setup import *
import argparse
p=argparse.ArgumentParser();p.add_argument('run',type=Path);a=p.parse_args()
run=ROOT/a.run;m=json.loads((run/'manifest.json').read_text());sy=m['symbols']
exe=ROOT/m['executable'];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(exe)==m['executable_sha256']
for n,h in m['source']['files'].items():assert sha(run/'source'/n)==h
cp=lambda p:'/work/'+str(p.relative_to(ROOT))
args=['+program='+cp(run/'program.hex'),'+payload='+cp(run/'empty.hex'),'+firmware='+cp(run/'empty.hex')]
for flag,label in [('begin_pc','body_begin'),('end_pc','body_end'),('stores_begin','stores_begin'),('stores_end','stores_end'),
                   ('irq_marker','irq_marker'),('forbidden_fault','forbidden_fault_store'),('forbidden_irq','forbidden_irq_store')]:
 args.append(f'+{flag}={sy[label]:x}')
args+=m['runtime_args']
docker=['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',str(ROOT)+':/work','-w','/work','--entrypoint',cp(exe),'jotego/simulator:arm64']
rows=[]
for name,flag,reason in [('wrong-post-byte','+post_bad=1','post physical byte oracle'),
                         ('wrong-stream-byte','+corrupt_oracle=1','physical cache mutation order/slot/word/bytes mismatch seq=0')]:
 log=run/(name+'.log');assert not log.exists()
 with log.open('w') as f:r=subprocess.run(docker+args+[flag],cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
 text=log.read_text();assert r.returncode!=0 and reason in text and 'PASS overlap' not in text
 rows.append(dict(name=name,status='EXPECTED_FAILURE',returncode=r.returncode,reason=reason,log_sha256=sha(log)))
assert sha(exe)==m['executable_sha256']
(run/'negative.json').write_text(json.dumps(dict(status='PASS',executable_sha256=sha(exe),rows=rows),indent=2)+'\n')
print('PASS both wrong physical-byte controls rejected with identical executable')
