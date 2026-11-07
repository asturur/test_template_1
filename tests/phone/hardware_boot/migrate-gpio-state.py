#!/usr/bin/env python3
"""Versioned RTL checkpoint migration: add only the derived UEM route2a wire.

All guest/CPU/device state must survive an exact reverse-conversion check.
Never use this for changed state registers, RAM layouts or other hierarchy edits.
"""
import argparse, hashlib, json, re, shutil, subprocess
from pathlib import Path

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def norm(s):
    s=re.sub(r'0x[0-9a-fA-F]+ULL','CHECK',s)
    s=re.sub(r'\s+','',s)
    return s.replace('os<<tb__DOT__dut__DOT__board__DOT__route2a;','').replace('os>>tb__DOT__dut__DOT__board__DOT__route2a;','')
def edit_serializer(s,guard,forward,root):
    marker='void Vtb___024root::__Vdeserialize' if root else 'void Vtb::__Vdeserialize'
    first,last=s.split(marker,1)
    first=re.sub(r'(uint64_t __Vcheckval = )0x[0-9a-fA-F]+ULL',r'\g<1>'+guard,first)
    if root:
        if forward:
            old='    os<<tb__DOT__dut__DOT__dma_lcd_addr;'
            assert first.count(old)==1
            prefix='tb__DOT__dut__DOT__board__DOT__uem__DOT__cbus__DOT__'
            expression=f'({prefix}written[1] & (1u << 10)) ? {prefix}values[0x2a] : 0'
            first=first.replace(old,old+'\n    os << SData('+expression+');')
        else:
            old='    os<<tb__DOT__dut__DOT__board__DOT__route2a;\n'
            assert first.count(old)==1
            first=first.replace(old,'')
    return first+marker+last

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--old-prefix',type=Path,required=True);p.add_argument('--new-run',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    old=json.loads((a.old_prefix.parent/'manifest.json').read_text());new=json.loads((a.new_run/'manifest.json').read_text())
    assert old['inputs']==new['inputs'] and old['image']==new['image']
    ob=Path('build/sim/logo-build')/old['source_identity'][:16];nb=Path('build/sim/logo-build')/new['source_identity'][:16]
    files=['Vtb___024root__Slow.cpp']
    def declarations(folder):
        found={}
        for line in (folder/'Vtb___024root.h').read_text().splitlines():
            line=line.strip()
            if line.startswith(('CData','SData','IData','QData','VlUnpacked<','VlWide<','VlTriggerVec<')) and line.endswith(';'):
                typename,name=line[:-1].rsplit(' ',1);found[name]=typename
        return found
    before_types,after_types=declarations(ob),declarations(nb)
    assert set(after_types)-set(before_types)=={'tb__DOT__dut__DOT__board__DOT__route2a'}
    assert not set(before_types)-set(after_types)
    assert all(before_types[k]==after_types[k] for k in before_types),'existing state type changed'
    assert after_types['tb__DOT__dut__DOT__board__DOT__route2a']=='SData/*15:0*/'
    for name in files:assert norm((ob/name).read_text())==norm((nb/name).read_text()),'serialization change exceeds derived route wire'
    # Verify all other serializers byte for byte, including array loops.
    for f in ob.glob('*.cpp'):
        if f.name not in files and '__Vserialize' in f.read_text():assert f.read_bytes()==(nb/f.name).read_bytes(),f.name
    work=Path('scratch/logo-bringup/state-migration');work.mkdir(exist_ok=True)
    a.output.mkdir(parents=True,exist_ok=False)
    cycle=int(a.old_prefix.name.rsplit('-',1)[1]);dest=a.output/('checkpoint-'+str(cycle))
    docker=['docker','run','--rm','--network','none','--platform','linux/arm64','-v',str(Path.cwd())+':/work','-w','/work','--entrypoint']
    guards={b:re.search(r'uint64_t __Vcheckval = (0x[0-9a-fA-F]+ULL)',(b/'Vtb___024root__Slow.cpp').read_text()).group(1) for b in (ob,nb)}
    main=work/'convert.cpp';main.write_text('#include "Vtb.h"\n#include "verilated_save.h"\nint main(int n,char**v){if(n!=3)return 1;VerilatedContext c;Vtb m(&c);VerilatedRestore r;r.open(v[1]);r>>m;r.close();VerilatedSave s;s.open(v[2]);s<<m;s.close();}\n')
    def build_convert(label,source,target,src,dst,forward):
        edits=[]
        for name in files:
            f=work/(label+'-'+name);f.write_text(edit_serializer((source/name).read_text(),guards[target],forward,name!='Vtb.cpp'));edits.append(str(f))
        exe=work/label
        cmd=docker+['g++','jotego/simulator:arm64','-std=c++17','-I/usr/local/verilator/share/verilator/include','-I/usr/local/verilator/share/verilator/include/vltstd','-I'+str(source),str(main)]+edits+[str(source/x) for x in ('Vtb__ALL.a','verilated.o','verilated_save.o','verilated_threads.o')]+['-pthread','-latomic','-o',str(exe)]
        subprocess.run(cmd,check=True)
        subprocess.run(docker+[str(exe),'jotego/simulator:arm64',str(src),str(dst)],check=True)
    before=Path(str(a.old_prefix)+'.cpu');after=Path(str(dest)+'.cpu');roundtrip=work/'roundtrip.cpu'
    build_convert('forward',ob,nb,before,after,True)
    build_convert('reverse',nb,ob,after,roundtrip,False)
    assert sha(before)==sha(roundtrip),'CPU/device/guest state changed in conversion'
    assert after.stat().st_size==before.stat().st_size+2,'unexpected serialized size'
    shutil.copyfile(str(a.old_prefix)+'.host',str(dest)+'.host')
    new.update(restore=str(a.old_prefix),cycles_target=cycle,diagnostic_fork='Pre-self-test state format migration plus reviewed IRQ/GPIO fixes; not a cold final-model run',migration={'kind':'one derived 16-bit route2a wire; no guest state edits','old_prefix':str(a.old_prefix),'old_source_identity':old['source_identity'],'old_cpu_sha256':sha(before),'roundtrip_sha256':sha(roundtrip),'new_cpu_sha256':sha(after),'host_sha256':sha(str(dest)+'.host'),'script_sha256':sha(__file__)})
    (a.output/'manifest.json').write_text(json.dumps(new,indent=2)+'\n');print(dest)
if __name__=='__main__':main()
