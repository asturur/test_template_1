#!/usr/bin/env python3
"""Publish only the authorized fit-only tree via gh; preserve local Git state."""
from pathlib import Path
import json,subprocess
ROOT=Path(__file__).resolve().parents[2]
out=ROOT/'build/fit/probe-retime-20261116'
repo='asturur/test_template_1'
assert not (out/'submission.json').exists(), 'Already submitted; collect the existing run'
def api(endpoint,payload=None):
 cmd=['gh','api',f'repos/{repo}/{endpoint}'.rstrip('/')]
 if payload is not None:
  p=out/'api-request.json';p.write_text(json.dumps(payload));cmd+=['--method','POST','--input',str(p)]
 raw=subprocess.check_output(cmd,cwd=ROOT,text=True)
 return json.loads(raw) if raw else None
# Repository identity proven against origin's old name and authorized control run.
assert api('')['id']==1434988755
assert api('actions/runs/43866215058')['head_sha']=='9c948da8da413a882e0fe8e559c380ea0cadabf4'
tree=api('git/trees',json.loads((out/'tree-request.json').read_text()))
(out/'remote-tree.json').write_text(json.dumps(tree,indent=2)+'\n')
commit=api('git/commits',{'message':'Fit-only: measure exact Stop 3C registered probe at seed 42','tree':tree['sha'],'parents':['9c948da8da413a882e0fe8e559c380ea0cadabf4']})
(out/'remote-commit.json').write_text(json.dumps(commit,indent=2)+'\n')
tag='fit-only/probe-retime-3c-20261116-s42-01'
api('git/refs',{'ref':'refs/tags/'+tag,'sha':commit['sha']})
identity={'repo':repo,'repository_id':1434988755,'tag':tag,'sha':commit['sha'],'tree':tree['sha'],'base':'9c948da8da413a882e0fe8e559c380ea0cadabf4','workflow':'ci_build.yml','seed':42,'debugger':True}
(out/'submission.json').write_text(json.dumps(identity,indent=2)+'\n')
api('actions/workflows/ci_build.yml/dispatches',{'ref':tag,'inputs':{'seed':'42','enable_debugger':'true'}})
print(json.dumps(identity,indent=2))
