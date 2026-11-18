#!/usr/bin/env python3
"""Publish one scoped, hash-qualified master commit using gh only."""
import argparse,datetime,hashlib,json,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/fit/tlb-matched-20261117';REPO='asturur/test_template_1'
p=argparse.ArgumentParser();p.add_argument('variant',choices=['5l','banked']);a=p.parse_args();out=OUT/a.variant

def git(*args):return subprocess.check_output(['git',*args],cwd=ROOT,text=True).strip()
def api(endpoint,payload=None,method='POST'):
    cmd=['gh','api',f'repos/{REPO}/{endpoint}']
    if payload is not None:
        path=out/'request.json';path.write_text(json.dumps(payload));cmd+=['--method',method,'--input',str(path)]
    raw=subprocess.check_output(cmd,cwd=ROOT,text=True);return json.loads(raw) if raw.strip() else None
assert not (out/'publication.json').exists(),'Already published; do not dispatch twice'
assert git('branch','--show-current')=='master'
staged=set(git('diff','--cached','--name-only').splitlines())
q=json.loads((out/'qualification.json').read_text());assert q['status']=='PASS'
for n,h in q['compiled_RTL_sha256'].items():assert hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h,n
assert 'OK: rtl/arm ==' in (out/'replay.log').read_text()
files=json.loads((out/'promoted-files.json').read_text())
module='cpu_late_operand' if a.variant=='5l' else 'tlb_area'
files += [str(p.relative_to(ROOT)) for p in (ROOT/f'tests/cpu/{module}').rglob('*') if p.is_file() and '__pycache__' not in str(p) and p.suffix in ['.py','.sv','.vh','.md']]
files += ['docs/cpu-late-operand.md','docs/evidence/cpu-late-operand-20261117.json','docs/evidence/cpu-late-operand-six-20261117.json','docs/tlb-matched-fit.md'] if a.variant=='5l' else ['docs/tlb-area.md','docs/evidence/tlb-area-20261117.json']
files=sorted(set(files));assert staged<=set(files),'Preserve unrelated staging';parent=git('rev-parse','HEAD');assert api('git/ref/heads/master')['object']['sha']==parent
subprocess.run(['git','add','--',*files],cwd=ROOT,check=True)
names=git('diff','--cached','--name-only').splitlines();assert set(names)<=set(files)
subprocess.run(['git','diff','--cached','--check'],cwd=ROOT,check=True)
entries=[]
for n in names:
    raw=subprocess.check_output(['git','show',':'+n],cwd=ROOT);assert raw==(ROOT/n).read_bytes()
    entries.append(dict(path=n,mode='100644',type='blob',content=raw.decode()))
# Before upload, compare every selected input against the previous immutable fit.
base=json.loads((ROOT/'build/fit/combined-5jk-20261117/summary.json').read_text())['source']['compiled_source_sha256']
expected={n:q['compiled_RTL_sha256'].get(n,h) for n,h in base.items()};assert len(expected)==178
for n,h in expected.items():
    raw=subprocess.check_output(['git','show',':'+n],cwd=ROOT)
    if n=='Template.qsf':assert raw==subprocess.check_output(['git','show','ccba54f:'+n],cwd=ROOT),n
    else:assert hashlib.sha256(raw).hexdigest()==h,n
(out/'expected-inputs.json').write_text(json.dumps(expected,indent=2)+'\n')
tree=api('git/trees',dict(base_tree=git('rev-parse','HEAD^{tree}'),tree=entries));assert tree['sha']==git('write-tree')
name,email=re.match(r'(.*?) <(.*?)>',git('var','GIT_AUTHOR_IDENT')).groups()
now=datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0);author=dict(name=name,email=email,date=now.isoformat().replace('+00:00','Z'))
message=('perf(cpu): capture late load operands' if a.variant=='5l' else 'perf(mmu): bank main TLB tags in RAM')+'\n'
commit=api('git/commits',dict(message=message,tree=tree['sha'],parents=[parent],author=author,committer=author))
raw=f"tree {tree['sha']}\nparent {parent}\nauthor {name} <{email}> {int(now.timestamp())} +0000\ncommitter {name} <{email}> {int(now.timestamp())} +0000\n\n{message}"
local=subprocess.check_output(['git','hash-object','-t','commit','-w','--stdin'],input=raw,cwd=ROOT,text=True).strip();assert local==commit['sha']
(out/'publication.json').write_text(json.dumps(dict(repo=REPO,sha=local,parent=parent,files=names),indent=2)+'\n')
api('git/refs/heads/master',dict(sha=local,force=False),'PATCH')
subprocess.run(['git','update-ref','refs/heads/master',local,parent],cwd=ROOT,check=True)
assert api('commits/master')['sha']==git('rev-parse','HEAD')==local
api('actions/workflows/ci_build.yml/dispatches',dict(ref='master',inputs=dict(seed='42',enable_debugger='true')))
(out/'dispatched.json').write_text(json.dumps(dict(sha=local,seed=42,debugger=True),indent=2)+'\n')
print('Published and dispatched exactly once:',local)
