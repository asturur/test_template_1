"""Replay the same game guests on the archived stock donor bench."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import re
import subprocess
import struct
from collections import Counter
import sys
from pathlib import Path

HERE=Path(__file__).resolve().parent
PEER=HERE.parent/'tlb_three_mapping'
sys.path.insert(0,str(PEER))
from build import CPU, DOCKER, IMAGE, OUT, ROOT, command, cpath, replace, save, sha
from run import prepare
from source import support

DONOR=ROOT.parent/'ngage2'
REVISION='23541bb5519972eccd38eb6a4912472a50b5b6fc'
SOURCES=('rtl/cpu/arm925t_gen.v','sim/stubs/altsyncram.sv','sim/stubs/altdpram.sv')
PROFILES=('0:0','2:9')


def harness(scan,jpeg):
    # The archived donor responder synthesizes its scalar/line-stream
    # interface over a 16-bit/cycle backend with the established waits.
    path=CPU/'ngage2_compare/run.py'
    source=path.read_text()
    source=source[source.index('def donor_tb('):source.index('def main():')]
    scope={}
    exec(compile(source,str(path),'exec'),scope)
    tb=scope['donor_tb']((CPU/'spmark_payload/tb.v').read_text())
    tb=tb.replace("32'h10000000",'payload_base').replace("32'h10100000","(payload_base+32'h100000)")
    tb=replace(tb,'module bench;', 'module bench;\n'+(HERE/'donor.vh').read_text())
    tb=replace(tb,'    initial begin\n','    initial begin\n        if(!$value$plusargs("compare_trace=%d",trace_mode))trace_mode=0;\n')
    tb=replace(tb,'            if(retire) begin','            donor_sample();\n            if(retire) begin')
    tb=replace(tb,'start_payload_ops=payload_ops;start_helper_ops=helper_ops;',
               'start_payload_ops=payload_ops;start_helper_ops=helper_ops;donor_begin();')
    tb=replace(tb,'                windows=windows+1;','                donor_end();\n                windows=windows+1;')
    if jpeg:
        tb=replace(tb,"payload_base=32'h10000000","payload_base=32'h50500000")
    if scan:
        tb=tb.replace('ram[0:32767]','ram[0:65535]').replace('n<32768','n<65536')
        tb=tb.replace("32'h0a020000","32'h0a040000").replace('[16:2]','[17:2]')
        tb=replace(tb,"if(retire_pc>=32'h50300000 && retire_pc<32'h50400000)",
                   "if(retire_pc>=32'h50500000 && retire_pc<32'h50600000)")
    return tb


def compile_donor(out,scan,jpeg):
    saved=json.loads((ROOT/'build/sim/spmark-payload/ngage2-vs5c-donor06/manifest.json').read_text())
    assert saved['source']['commit']==REVISION
    for name in SOURCES:
        frozen=out/'source'/name
        frozen.parent.mkdir(exist_ok=True,parents=True)
        frozen.write_bytes(subprocess.check_output(['git','show',f'{REVISION}:{name}'],cwd=DONOR))
        assert sha(frozen)==saved['source']['dependencies'][name],name
    tb=out/'tb.v'
    tb.write_text(harness(scan,jpeg))
    exe=out/'obj/Vbench'
    command(DOCKER+['verilator',IMAGE,'--binary','--timing','--assert','-j','3',
        '-Wno-fatal','-Wno-lint','-DNGAGE_RUNTIME_TRACE','--top-module','bench',
        '--Mdir',cpath(exe.parent)]+[cpath(out/'source'/name) for name in SOURCES]+[cpath(tb)],
        out/'build.log')
    return dict(revision=REVISION,source={n:sha(out/'source'/n) for n in SOURCES},
                harness=sha(tb),executable=sha(exe),image=saved['image_id'])


def records(text,label):
    return [dict(re.findall(r'(\w+)=(\w+)',line)) for line in text.splitlines()
            if line.startswith(label+' ')]


def replica(out,case,profile,bad,repeat):
    iw,dw=profile.split(':')
    variant=case['variants'][bad]
    name=variant['name']
    log=out/f'{name}-{iw}-{dw}-{repeat}.log'
    rc=command(DOCKER+[cpath(out/'obj/Vbench'),IMAGE,
        '+program='+cpath(out/(name+'.hex')),'+payload='+cpath(out/(name+'-payload.hex')),
        '+firmware='+cpath(out/case['firmware']),f'+begin_pc={variant["begin"]:x}',
        f'+end_pc={variant["end"]:x}',f'+i_wait={iw}',f'+d_wait={dw}',
        '+max_cycles=90000000',f'+compare_trace={((2 if case['suite']=='jpeg' else 1) if not bad and not repeat else 0)}'],log,negative=bad)
    text=log.read_text()
    if bad:
        assert rc and 'guest result check failed' in text
        return None
    obs=support.parse_log(text,case)
    oracle=case['oracle']
    effects=records(text,'DONOR_EFFECT')
    payload=records(text,'PAYLOAD_WINDOW')
    assert len(effects)==len(payload)==7
    expected_payload=oracle['payload_instructions'] if case['suite']=='scan' else oracle['instructions']
    expected_helper=oracle['helper_instructions'] if case['suite']=='scan' else 0
    if case['suite']=='jpeg':
        # Count the donor's architecturally visible Thumb BL suffixes, as in
        # the archived ngage2 benchmark, and validate their exact dynamic PCs.
        raw=case['rom']
        normalized={int(pc,16):n for pc,n in oracle['pcs'].items()}
        suffixes={}
        for pc,n in normalized.items():
            h0,h1=struct.unpack_from('<HH',raw,pc-0x50000000)
            if h0&0xf800==0xf000 and h1&0xf800==0xf800:
                suffixes[pc+2]=n
        expected=Counter(normalized)+Counter(suffixes)
        if repeat==0:
            got=Counter(int(r['rpc'],16) for r in records(text,'DONOR_EDGE')
                        if r['ret']=='1' and 0x50300000<=int(r['rpc'],16)<0x50600000)
            assert got==expected,(case['id'],got-expected,expected-got)
        expected_payload=sum(n for pc,n in expected.items() if 0x50500000<=pc<0x50600000)
        expected_helper=sum(n for pc,n in expected.items() if 0x50300000<=pc<0x50400000)
        obs['thumb_suffix_retirements']=sum(suffixes.values())
    for window,effect,counts in zip(obs['windows'],effects,payload):
        assert window['index']==int(effect['index'])==int(counts['index'])
        assert int(counts['payload_retire_proxy'])==expected_payload+(case['suite']!='jpeg'), counts
        assert int(counts['helper_retire_proxy'])==expected_helper, counts
        if case['suite']!='jpeg':
            assert int(effect['count'])==oracle.get('memory_writes',oracle.get('stores')),effect
        window.update(effect=effect,payload=counts)
    return obs


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('name')
    kind=parser.add_mutually_exclusive_group()
    kind.add_argument('--scan',action='store_true')
    kind.add_argument('--jpeg',action='store_true')
    parser.add_argument('--case',action='append')
    parser.add_argument('--workers',default=3,type=int)
    args=parser.parse_args()
    assert Path(args.name).name==args.name and args.name not in ('.','..')
    out=OUT/args.name
    out.mkdir(exist_ok=False,parents=True)
    manifest=compile_donor(out,args.scan,args.jpeg)
    cases=prepare(out,{'scan' if args.scan else 'jpeg' if args.jpeg else 'games'})
    if args.jpeg:
        rom=(ROOT/'build/firmware/nem4-factory/core.bin').read_bytes()
        for case in cases.values():
            case['rom']=rom
    selected=set(args.case or cases)
    assert selected<=cases.keys()
    save(out/'result.json',dict(status='INCOMPLETE',manifest=manifest,rows=[]))
    report=dict(status='PASS',manifest=manifest,rows=[])
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures={}
        for key in sorted(selected):
            for profile in PROFILES:
                futures[key,profile]=[pool.submit(replica,out,cases[key],profile,False,i) for i in range(2)]
                futures[key,profile].append(pool.submit(replica,out,cases[key],profile,True,0))
        for (key,profile),jobs in futures.items():
            a,b,negative=[j.result() for j in jobs]
            assert a==b and negative is None
            report['rows'].append(dict(case=key,profile=profile,variants=list(cases[key]['variants'].values()),
                                       oracle=cases[key]['oracle'],repeats=2,negative=True,**a))
            print(key,profile,a['body_cycles_median'],'PASS',flush=True)
    save(out/'result.json',report)


if __name__=='__main__':
    main()
