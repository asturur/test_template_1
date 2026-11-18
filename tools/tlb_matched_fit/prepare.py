#!/usr/bin/env python3
"""Recreate and verify both qualified sources without importing dirty work."""
import difflib, hashlib, importlib.util, io, json, subprocess, tarfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/fit/tlb-matched-20261117'
def prepare():
    evidence=json.loads((ROOT/'docs/evidence/tlb-area-20261117.json').read_text())
    names=[n for n in evidence['candidate_manifest']['source']['files'] if n.startswith('rtl/') and n.endswith(('.sv','.svh','.v','.vh'))]
    assert len(names)==60
    for variant,module in [('5l','cpu_late_operand'),('banked','tlb_area')]:
        dest=OUT/variant/'source';dest.mkdir(parents=True,exist_ok=True)
        tarfile.open(fileobj=io.BytesIO(subprocess.check_output(['git','archive','ccba54f','rtl'],cwd=ROOT))).extractall(dest,filter='data')
        spec=importlib.util.spec_from_file_location(variant,ROOT/f'tests/cpu/{module}/setup.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);m.overlay(dest,True)
        expected={n:evidence['control_manifest' if variant=='5l' else 'candidate_manifest']['source']['files'][n] for n in names}
        for n,h in expected.items():assert hashlib.sha256((dest/n).read_bytes()).hexdigest()==h,(variant,n)
        (OUT/variant/'qualification.json').write_text(json.dumps(dict(status='PASS',compiled_RTL_sha256=expected,evidence='docs/evidence/tlb-area-20261117.json'),indent=2)+'\n')
    print('PASS both exact qualified 60-file manifests')
def promote(variant,number,title):
    q=json.loads((OUT/variant/'qualification.json').read_text());patch=[];changed=[]
    for n in q['compiled_RTL_sha256']:
        new=(OUT/variant/'source'/n).read_text();old=subprocess.check_output(['git','show','HEAD:'+n],cwd=ROOT).decode()
        if new==old:continue
        changed.append(n);(ROOT/n).write_text(new)
        if n.startswith('rtl/arm/'):
            path='src/rtl/'+Path(n).name
            patch.extend(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='a/'+path,tofile='b/'+path))
    assert len(changed)==(2 if variant=='5l' else 7),changed
    name=f'patches/zap/{number}-{title}.patch';(ROOT/name).write_text(''.join(patch))
    p=ROOT/'rtl/arm/UPSTREAM.json';d=json.loads(p.read_text());assert name not in d['modifications'];d['modifications'].append(name);p.write_text(json.dumps(d,indent=2)+'\n')
    p=ROOT/'rtl/arm/README.md';p.write_text(p.read_text()+f'\nPatch{number} records the exact qualified {variant} integration. See\ndocs/'+('cpu-late-operand.md' if variant=='5l' else 'tlb-area.md')+'.\n')
    (OUT/variant/'promoted-files.json').write_text(json.dumps(changed+[name,'rtl/arm/UPSTREAM.json','rtl/arm/README.md'],indent=2)+'\n')
    print('Promoted:',changed)
if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('action',choices=['prepare','5l','banked']);a=p.parse_args()
    if a.action=='prepare':prepare()
    else:promote(a.action,'0081' if a.action=='5l' else '0082','late-arithmetic-operand' if a.action=='5l' else 'bank-main-tlb-tags')
