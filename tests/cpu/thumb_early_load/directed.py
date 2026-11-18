"""Qualify early Thumb owners on the actual CPU with a checked fault/recovery guest."""
import argparse
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent/'tlb_three_mapping'))
from build import DOCKER, IMAGE, OUT, command, cpath, replace, save, sha
from source import compiler_sources
from run import assemble, hexfile

PAIRS = ('imm_low','imm_high','sp_low','sp_high','cold_load','fault_load')
EXCLUDED = ('literal_load','register_load','byte_load','half_load','macro_ldm','macro_pop')


def audit(text, symbols, thumb):
    def records(label):
        return [dict(word.split('=') for word in line.split()[1:])
                for line in text.splitlines() if line.startswith(label+' ')]
    def group(label, name):
        return [r for r in records(label) if int(r['pc'],16)==symbols[name]]
    for name in PAIRS:
        lines = group('CHECK_EXEC',name)
        assert lines and {int(r['class']) for r in lines}=={int(thumb)}, (name,lines)
        early = [r for r in group('CHECK_OFFER',name) if r['early']=='1']
        assert bool(early)==thumb, (name,early)
    for name in EXCLUDED:
        lines = group('CHECK_EXEC',name)
        assert lines and not any(r['class']=='1' or r['hint']=='1' for r in lines), (name,lines)
        assert not any(r['early']=='1' for r in group('CHECK_OFFER',name))
    for name in ('imm_low','imm_high','sp_low','sp_high','cold'):
        producer = symbols['cold_load' if name=='cold' else name]
        uses = group('CHECK_LATE',name+'_use')
        assert bool(uses)==thumb and all(int(r['producer'],16)==producer for r in uses), (name,uses)
        assert len(group('CHECK_RET',name+'_use'))==1
    rejected = group('CHECK_LATE','fault_use')
    assert bool(rejected)==thumb
    assert not group('CHECK_RET','fault_use')
    fault, = group('CHECK_FAULT','fault_load')
    assert int(fault['far'],16)==0x90000004 and int(fault['fsr'],16)==5
    assert len(group('CHECK_RET','thumb_resume'))==len(group('CHECK_RET','finish_arm'))==1
    cold = group('CHECK_OFFER','cold_load')
    assert len(cold)>2 and cold[-1]['ack']=='1' and all(r['ack']=='0' for r in cold[:-1])
    assert {int(r['address'],16) for r in cold}=={0x80005000}
    result, = [line for line in text.splitlines() if line.startswith('RESULT ')]
    return dict(result=result,cold_offers=len(cold),fault=fault,fault_consumer_accepted=bool(rejected),
                successful_dependents=5,excluded=list(EXCLUDED))


def run(out, build, thumb):
    out.mkdir(parents=True,exist_ok=False)
    manifest=json.loads((build/'manifest.json').read_text())
    src=build/'source'
    assert all(sha(src/name)==h for name,h in manifest['source']['files'].items())
    tb=replace((build/'tb.v').read_text(), 'module bench;',
               'module bench;\n'+(HERE/'directed.vh').read_text())
    (out/'tb.v').write_text(tb)
    exe=out/'obj/Vbench'
    command(DOCKER+['verilator',IMAGE,'--binary','--timing','--assert','-j','2',
                    '-Wno-fatal','-Wno-lint','-DNGAGE_RUNTIME_TRACE','-DBENCH_HAS_LINE',
                    '-GLINE_ENABLE=1','--top-module','bench','--Mdir',cpath(exe.parent),
                    '-I'+cpath(build),'-I'+cpath(src/'rtl/arm')]
            +[cpath(path) for path in compiler_sources(src)]+[cpath(out/'tb.v')],out/'build.log')
    raw,symbols=assemble(out,'directed',(HERE/'directed.S').read_text())
    hexfile(out/'directed.hex',raw)
    hexfile(out/'empty.hex',bytes(4))
    rows=[]
    for profile in ('0:0','2:9','0:97'):
        iw,dw=profile.split(':')
        observations=[]
        for repeat in range(2):
            log=out/f'{iw}-{dw}-{repeat}.log'
            command(DOCKER+[cpath(exe),IMAGE,'+program='+cpath(out/'directed.hex'),
                            '+payload='+cpath(out/'empty.hex'),'+firmware='+cpath(out/'empty.hex'),
                            '+begin_pc=1','+end_pc=2',f'+i_wait={iw}',f'+d_wait={dw}',
                            '+max_cycles=1000000','+ngage-compact-trace'],log)
            observations.append(audit(log.read_text(),symbols,thumb))
        assert observations[0]==observations[1]
        rows.append(dict(profile=profile,**observations[0]))
        print(build.name,profile,'PASS',flush=True)
    save(out/'result.json',dict(status='PASS',rows=rows,source=manifest['source'],
                                guest_sha256=sha(out/'directed.bin'),symbols=symbols))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('name')
    parser.add_argument('--build',required=True)
    parser.add_argument('--thumb',action='store_true')
    args=parser.parse_args()
    run(OUT/args.name,OUT/args.build,args.thumb)
