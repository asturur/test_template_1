#!/usr/bin/env python3
"""Passive original-workload main-bank frequency on exact offline5L."""
import argparse,sys,importlib.util
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser(add_help=False);p.add_argument('--jpeg',action='store_true');p.add_argument('--candidate',action='store_true');a,rest=p.parse_known_args()
spec=importlib.util.spec_from_file_location('area_late',ROOT/'tests/cpu/cpu_late_operand/setup.py');late=importlib.util.module_from_spec(spec);spec.loader.exec_module(late)
sys.path.insert(0,str(ROOT/'tests/cpu/spmark_payload'))
import run as common
original=common.support
def support():
    b=original();freeze=b.snapshot
    def snapshot(destination,revision=None,root=ROOT):
        old=freeze(destination,late.BASE,root)
        if a.candidate:
            spec=importlib.util.spec_from_file_location('banked_area',HERE/'setup.py');area=importlib.util.module_from_spec(spec);spec.loader.exec_module(area);area.overlay(destination,True)
        else:late.overlay(destination,True)
        return b.source_manifest(destination,old['commit'],'area-frequency-exact5L')
    b.snapshot=snapshot;return b
common.support=support
def instrument(tb):
    tb=tb.replace('module bench;','module bench;\n'+(HERE/'tlb_observe.vh').read_text(),1)
    tb=tb.replace('            if(retire && retire_pc==begin_pc)', '            area_sample();\n            if(retire && retire_pc==begin_pc)',1)
    tb=tb.replace('start_helper_ops=helper_ops;','start_helper_ops=helper_ops;area_begin();',1)
    tb=tb.replace('                windows=windows+1;','                area_end();\n                windows=windows+1;',1)
    tb=tb.replace('                        $display("RESULT ', '                        area_dump();\n                        $display("RESULT ',1)
    return tb
if a.jpeg:
    path=ROOT/'tests/cpu/cache_probe_retime/jpeg_run.py'
    source=path.read_text().replace("'-j','3'","'-j','1'").replace('def cases():return all_cases()','def cases():return all_cases()[:1]')
    source=source.replace(" (O/'tb.v').write_text(tb)"," tb=instrument(tb)\n (O/'tb.v').write_text(tb)")
    sys.argv=[str(path),*rest]
    exec(compile(source,str(path),'exec'),dict(__file__=str(path),__name__='__main__',instrument=instrument))
else:
    path=Path(common.__file__)
    source=path.read_text().replace("shutil.copyfile(tb, out/'tb.v')", "(out/'tb.v').write_text(instrument(tb.read_text()))\n    tb=out/'tb.v'")
    source=source.replace("'-I'+cpath(source/'rtl/arm')]+", "'-I'+cpath(source/'rtl/arm')]+")
    sys.argv=[str(path),*rest,'--jobs','1']
    source=source.replace('bench = support()', 'bench = area_support()')
    common.__dict__['area_support']=support
    common.__dict__['__name__']='__main__'
    common.__dict__['instrument']=instrument
    exec(compile(source,str(path),'exec'),common.__dict__)
