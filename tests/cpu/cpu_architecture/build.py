"""Freeze the combined 5L/banked/third/Thumb reference and optional structural overlay."""
import argparse
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PEER = HERE.parent/'tlb_three_mapping'
sys.path.insert(0,str(PEER))
from source import support
import build as peer

REFERENCE = '1928aeef68cbd65699014854326c38101f5249a7'
CPU_DIFF = {'rtl/arm/zap_core.sv','rtl/arm/zap_predecode_main.sv','rtl/arm/zap_issue_main.sv'}


def augment(observer, path, prefix):
    observer=path.read_text()+observer
    for task in ('begin','sample','end'):
        anchor=f'task mapping_{task};'
        index=observer.index('    begin\n',observer.index(anchor))+len('    begin\n')
        observer=observer[:index]+f'        {prefix}_{task}();\n'+observer[index:]
    return observer


def freeze(dest, third_slot, prototype=False):
    base=support.snapshot(dest,REFERENCE)
    root=peer.ROOT
    doc=root/'docs/evidence/cpu-thumb-load-20261118.json.gz'
    import gzip,json
    recorded=json.loads(gzip.decompress(doc.read_bytes()))['manifests']['combined_banked_third']['source']
    assert base['files']==recorded['files'] and base['source_id']==recorded['source_id']
    patch=HERE.parent/'thumb_early_load/thumb-load.patch'
    subprocess.run(['git','apply','--no-index','--directory='+str(dest.relative_to(root)),patch],cwd=root,check=True)
    ref=support.source_manifest(dest,REFERENCE,'banked third slot with qualified Thumb')
    assert ref['files'].keys()==base['files'].keys()
    assert {k for k,h in base['files'].items() if ref['files'][k]!=h}==CPU_DIFF
    assert peer.sha(patch)==json.loads(gzip.decompress(doc.read_bytes()))['driver_hashes']['thumb-load.patch']
    if prototype:
        from prototype import overlay
        overlay(dest)
        return support.source_manifest(dest,REFERENCE,'structural experiment')
    return ref


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('name')
    p.add_argument('--scan',action='store_true')
    p.add_argument('--prototype',action='store_true')
    p.add_argument('--jobs',type=int,default=3)
    a=p.parse_args()
    assert Path(a.name).name==a.name and a.name not in ('.','..')
    peer.freeze=lambda dest,third:freeze(dest,third,a.prototype)
    text=(PEER/'observe.vh').read_text()
    text=augment(text,HERE.parent/'thumb_early_load/observe.vh','thumb')
    text=augment(text,HERE/'observe.vh','arch')
    peer.build(peer.OUT/a.name,True,a.jobs,a.scan,text.encode())


if __name__=='__main__':
    main()
