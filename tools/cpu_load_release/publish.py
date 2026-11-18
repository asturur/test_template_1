#!/usr/bin/env python3
"""Publish the reviewed staged release through gh Git Database, then one build."""
import datetime,hashlib,json,os,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];os.chdir(ROOT)
OUT=ROOT/'build/fit/combined-5jk-20261117';REPO='asturur/test_template_1'
def git(*args):return subprocess.check_output(['git',*args],text=True).strip()
def api(endpoint,payload=None,method=None):
 args=['gh','api','repos/'+REPO+'/'+endpoint]
 if payload is not None:
  f=OUT/'request.json';f.write_text(json.dumps(payload));args+=['--method',method or 'POST','--input',str(f)]
 raw=subprocess.check_output(args,text=True);return json.loads(raw) if raw.strip() else None
expected=json.loads((OUT/'qualification.json').read_text());assert expected['status']=='PASS'
for n,h in expected['compiled_RTL_sha256'].items():assert hashlib.sha256(Path(n).read_bytes()).hexdigest()==h
assert 'OK: rtl/arm ==' in (OUT/'replay.log').read_text()
assert git('branch','--show-current')=='master'
parent=git('rev-parse','HEAD');assert api('git/ref/heads/master')['object']['sha']==parent
names=git('diff','--cached','--name-only').splitlines()
allowed={'rtl/arm/zap_core.sv','rtl/arm/README.md','rtl/arm/UPSTREAM.json','patches/zap/0080-pipeline-load-lookup.patch','docs/cpu-load-release.md','tests/cpu/cpu_load_lookup/qualify.py','tests/cpu/cpu_load_lookup/setup.py','tests/cpu/cpu_load_lookup/rtl/arm/zap_core.sv'}
assert set(names)==allowed,(set(names)-allowed,allowed-set(names))
subprocess.run(['git','diff','--cached','--check'],check=True)
entries=[]
for n in names:
 raw=subprocess.check_output(['git','show',':'+n]);assert raw==Path(n).read_bytes()
 entries.append(dict(path=n,mode='100644',type='blob',content=raw.decode()))
tree=api('git/trees',dict(base_tree=git('rev-parse','HEAD^{tree}'),tree=entries))
assert tree['sha']==git('write-tree')
identity=git('var','GIT_AUTHOR_IDENT');name,email=re.match(r'(.*?) <(.*?)>',identity).groups()
now=datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0);date=now.isoformat().replace('+00:00','Z')
author=dict(name=name,email=email,date=date)
message='perf(cpu): pipeline resident load lookup\n\nAdvance dependent span consumers one clock while retaining P1 throughput.\nOriginal six kernels and Thumb JPEG pass matched 5F regressions.\n'
commit=api('git/commits',dict(message=message,tree=tree['sha'],parents=[parent],author=author,committer=author))
raw=f"tree {tree['sha']}\nparent {parent}\nauthor {name} <{email}> {int(now.timestamp())} +0000\ncommitter {name} <{email}> {int(now.timestamp())} +0000\n\n{message}"
local=subprocess.check_output(['git','hash-object','-t','commit','-w','--stdin'],input=raw,text=True).strip()
assert local==commit['sha'],(local,commit['sha'])
(OUT/'publication.json').write_text(json.dumps(dict(repo=REPO,sha=local,parent=parent,files=names),indent=2)+'\n')
api('git/refs/heads/master',dict(sha=local,force=False),method='PATCH')
subprocess.run(['git','update-ref','refs/heads/master',local,parent],check=True)
assert api('commits/master')['sha']==git('rev-parse','HEAD')==local
api('actions/workflows/ci_build.yml/dispatches',dict(ref='master',inputs=dict(seed='42',enable_debugger='true')))
print('Published and dispatched exactly once:',local,flush=True)
