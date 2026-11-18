#!/usr/bin/env python3
"""Publish only matched-fit evidence and reproduction helpers, without dispatch."""
import datetime,hashlib,json,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'build/fit/tlb-matched-20261117';REPO='asturur/test_template_1'
def git(*args):return subprocess.check_output(['git',*args],cwd=ROOT,text=True).strip()
def api(endpoint,payload=None,method='POST'):
    cmd=['gh','api',f'repos/{REPO}/{endpoint}']
    if payload is not None:
        path=OUT/'report-request.json';path.write_text(json.dumps(payload));cmd+=['--method',method,'--input',str(path)]
    raw=subprocess.check_output(cmd,cwd=ROOT,text=True);return json.loads(raw) if raw.strip() else None
assert not (OUT/'report-publication.json').exists()
evidence=json.loads((ROOT/'docs/evidence/tlb-matched-fit-20261117.json').read_text());assert evidence['status']=='PASS matched physical comparison'
assert git('branch','--show-current')=='master' and not git('diff','--cached','--name-only')
parent=git('rev-parse','HEAD');assert parent==evidence['variants']['banked']['commit'];assert api('git/ref/heads/master')['object']['sha']==parent
files=['docs/tlb-matched-fit.md','docs/evidence/tlb-matched-fit-20261117.json','docs/tlb-area.md','docs/cpu-late-operand.md','tests/cpu/cpu_load_lookup/bench.py','tests/cpu/cpu_load_pipeline/bench.py','tests/cpu/cpu_load_pipeline/safety.py']
files += [str(p.relative_to(ROOT)) for p in (ROOT/'tools/tlb_matched_fit').glob('*') if p.is_file() and p.suffix in ['.py','.md']]
qualified=json.loads((ROOT/'docs/evidence/cpu-late-operand-20261117.json').read_text())['support_inputs']
for n in files:
    if n.startswith('tests/'):assert hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==qualified[n],n
subprocess.run(['git','add','--',*files],cwd=ROOT,check=True)
# Preserve other chats' unrelated status/index edits in the working tree.
for n in ['docs/status.md','docs/README.md']:
    base=subprocess.check_output(['git','show','HEAD:'+n],cwd=ROOT).decode();work=(ROOT/n).read_text()
    if n.endswith('status.md'):
        assert work.startswith('## 2026-11-17 — Matched 5L / banked-TLB fits completed')
        prefix=work.split('\n## ',1)[0]+'\n\n';content=prefix+base
    else:
        rows=[line for line in work.splitlines() if line.startswith('| [') and any('['+v+']' in line for v in ['tlb-matched-fit.md','tlb-area.md','cpu-late-operand.md'])]
        rows=[r for r in rows if r.split('|')[1].strip().split(']')[0]+']' not in base]
        marker='| --- | --- |\n';assert marker in base;content=base.replace(marker,marker+'\n'.join(rows)+'\n',1)
    blob=subprocess.check_output(['git','hash-object','-w','--stdin'],input=content,cwd=ROOT,text=True).strip()
    subprocess.run(['git','update-index','--add','--cacheinfo','100644,'+blob+','+n],cwd=ROOT,check=True)
files+=['docs/status.md','docs/README.md'];names=git('diff','--cached','--name-only').splitlines();assert set(names)<=set(files)
subprocess.run(['git','diff','--cached','--check'],cwd=ROOT,check=True)
entries=[dict(path=n,mode='100644',type='blob',content=subprocess.check_output(['git','show',':'+n],cwd=ROOT).decode()) for n in names]
tree=api('git/trees',dict(base_tree=git('rev-parse','HEAD^{tree}'),tree=entries));assert tree['sha']==git('write-tree')
name,email=re.match(r'(.*?) <(.*?)>',git('var','GIT_AUTHOR_IDENT')).groups();now=datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0);author=dict(name=name,email=email,date=now.isoformat().replace('+00:00','Z'))
message='docs(cpu): record matched banked TLB fits\n';commit=api('git/commits',dict(message=message,tree=tree['sha'],parents=[parent],author=author,committer=author))
raw=f"tree {tree['sha']}\nparent {parent}\nauthor {name} <{email}> {int(now.timestamp())} +0000\ncommitter {name} <{email}> {int(now.timestamp())} +0000\n\n{message}"
local=subprocess.check_output(['git','hash-object','-t','commit','-w','--stdin'],input=raw,cwd=ROOT,text=True).strip();assert local==commit['sha']
(OUT/'report-publication.json').write_text(json.dumps(dict(repo=REPO,sha=local,parent=parent,files=names),indent=2)+'\n')
api('git/refs/heads/master',dict(sha=local,force=False),'PATCH');subprocess.run(['git','update-ref','refs/heads/master',local,parent],cwd=ROOT,check=True)
assert api('commits/master')['sha']==git('rev-parse','HEAD')==local
print('Published measured evidence without another build:',local)
