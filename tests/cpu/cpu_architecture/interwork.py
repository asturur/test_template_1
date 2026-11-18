"""Run alternating ARM/Thumb targets at the same address on both real CPU variants."""
import argparse
from pathlib import Path
import json
import sys

HERE=Path(__file__).resolve().parent
PEER=HERE.parent/'tlb_three_mapping'
sys.path.insert(0,str(PEER))
from build import DOCKER, IMAGE, OUT, command, cpath, replace, save, sha
from run import assemble, hexfile
from source import compiler_sources


def run(out,build,prototype):
    out.mkdir(parents=True,exist_ok=False)
    manifest=json.loads((build/'manifest.json').read_text())
    source=build/'source'
    assert all(sha(source/p)==h for p,h in manifest['source']['files'].items())
    tb=replace((build/'tb.v').read_text(),'module bench;',
               'module bench;\n'+(HERE/'interwork.vh').read_text())
    (out/'tb.v').write_text(tb)
    obj=out/'obj'
    command(DOCKER+['verilator',IMAGE,'--binary','--timing','--assert','-j','2',
        '-Wno-fatal','-Wno-lint','-DNGAGE_RUNTIME_TRACE','-DTHIRD_SLOT','-DBENCH_HAS_LINE',
        '-GLINE_ENABLE=1','--top-module','bench','--Mdir',cpath(obj),
        '-I'+cpath(build),'-I'+cpath(source/'rtl/arm')]
        +[cpath(p) for p in compiler_sources(source)]+[cpath(out/'tb.v')],out/'build.log')
    directed=(HERE.parent/'thumb_early_load/directed.S').read_text()
    prefix=directed.split(' ldr sp,=',1)[0].replace(' b abort_handler',' b fail')
    raw,symbols=assemble(out,'interwork',prefix+(HERE/'interwork.S').read_text())
    hexfile(out/'interwork.hex',raw)
    hexfile(out/'empty.hex',bytes(4))
    rows=[]
    for profile in ('0:0','2:9','0:97'):
        iw,dw=profile.split(':')
        repeat_rows=[]
        for i in range(2):
            log=out/f'{iw}-{dw}-{i}.log'
            command(DOCKER+[cpath(obj/'Vbench'),IMAGE,'+program='+cpath(out/'interwork.hex'),
                '+payload='+cpath(out/'empty.hex'),'+firmware='+cpath(out/'empty.hex'),
                '+begin_pc=1','+end_pc=2',f'+observed_bx={symbols["observed_bx"]:x}',
                '+max_cycles=1000000',f'+i_wait={iw}',f'+d_wait={dw}'],log)
            txt=log.read_text()
            rows_inner=[dict(word.split('=') for word in line.split()[1:])
                        for line in txt.splitlines() if line.startswith('INTERWORK ')]
            assert len(rows_inner)==48,rows_inner
            targets={int(r['target'],16) for r in rows_inner}
            assert len(targets)==2 and len({a>>1 for a in targets})==1,targets
            correct=sum(r['flush']=='0' for r in rows_inner)
            wrong_mode=sum(r['flush']=='1' and r['taken'] in ('2','3') and
                           (int(r['predicted'],16)^int(r['target'],16))==1 for r in rows_inner)
            if prototype:
                assert correct>0 and wrong_mode>=3,(correct,wrong_mode,rows_inner)
            result,=[line for line in txt.splitlines() if line.startswith('RESULT ')]
            repeat_rows.append(dict(profile=profile,result=result,confirmed_without_flush=correct,
                                    wrong_state_same_address_recovered=wrong_mode))
        assert repeat_rows[0]==repeat_rows[1]
        rows.append(repeat_rows[0])
        print(build.name,repeat_rows[0],flush=True)
    save(out/'result.json',dict(status='PASS',rows=rows,source=manifest['source'],program=sha(out/'interwork.bin')))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('name')
    p.add_argument('--build',required=True)
    p.add_argument('--prototype',action='store_true')
    a=p.parse_args()
    run(OUT/a.name,OUT/a.build,a.prototype)
