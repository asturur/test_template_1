import hashlib,json,os,shlex,subprocess
from pathlib import Path
p=Path('scratch/spmark-ldm-board-20261114')
f=p/'artifacts/ngage1-rbf/ngage1.rbf'
meta=json.loads((f.parent/'build-info.json').read_text())
assert meta['commit']=='22e5e14ffd56add5028907de94bcf4fd2bfa903c' and meta['fitter_seed']==44
b=f.read_bytes();assert 4000000<len(b)<6000000
sha=hashlib.sha256(b).hexdigest()
code="""import hashlib,json,os,sys
from pathlib import Path
expected=EXPECTED
size=SIZE
b=sys.stdin.buffer.read()
assert len(b)==size and hashlib.sha256(b).hexdigest()==expected
p=Path('/media/fat/_Console/ngage1.rbf');stage=p.with_name('.ngage1-22e5e14.rbf.tmp')
with stage.open('wb') as out:
 out.write(b);out.flush();os.fsync(out.fileno())
assert hashlib.sha256(stage.read_bytes()).hexdigest()==expected
os.replace(stage,p)
assert hashlib.sha256(p.read_bytes()).hexdigest()==expected
print(json.dumps(dict(path=str(p),bytes=len(b),sha256=expected,card_backup_created=False)))
""".replace('EXPECTED',repr(sha)).replace('SIZE',str(len(b)))
r=subprocess.run(['ssh','-S','scratch/ngage-diag.sock','-o','BatchMode=yes','root@192.168.1.176','python3 -c '+shlex.quote(code)],input=b,stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=True,timeout=60)
report=json.loads(r.stdout);report.update(meta)
(p/'deployment.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
