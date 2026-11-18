#!/usr/bin/env python3
"""Serial 5J replay: exact 5F versus P1 load start, one CPU executable per variant."""
import argparse
import importlib.util
import json
import re
import shutil
import statistics
import struct
import subprocess
import sys
from pathlib import Path
from setup import ROOT,HERE,BASE,overlay

sys.path.insert(0,str(ROOT/'tests/cpu/super_monkey_ball'))
import workload as smb
sys.path.insert(0,str(ROOT/'tests/cpu/spmark_payload'))
import workloads as sp
from oracle import verify
sys.path.insert(0,str(ROOT/'tests/cpu/donor_import'))
spec=importlib.util.spec_from_file_location('cpu_support',ROOT/'tests/cpu/donor_import/run.py')
support=importlib.util.module_from_spec(spec);spec.loader.exec_module(support)
IMAGE='jotego/simulator:arm64'

def sha(p):return smb.digest(p.read_bytes())
def save(p,v):p.write_text(json.dumps(v,indent=2,sort_keys=True)+'\n')
def cp(p):return '/work/'+str(p.relative_to(ROOT))
def hexfile(p,raw):
    raw+=bytes(-len(raw)%4)
    p.write_text(''.join(f'{v[0]:08x}\n' for v in struct.iter_unpack('<I',raw)))
def call(args,log,bad=False):
    with log.open('w') as f:
        f.write(json.dumps([str(a) for a in args])+'\n');f.flush()
        r=subprocess.run([str(a) for a in args],cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
    if r.returncode and not bad:raise RuntimeError(f'failed: {log}')
    return r.returncode
def assemble(out,name,text):
    path=out/name;path.with_suffix('.S').write_text(text)
    call(['arm-none-eabi-gcc','-c','-mcpu=arm920t','-marm',path.with_suffix('.S'),'-o',path.with_suffix('.o')],out/(name+'.assemble.log'))
    call(['arm-none-eabi-ld','-T',ROOT/'sim/programs/link.ld',path.with_suffix('.o'),'-o',path.with_suffix('.elf')],out/(name+'.link.log'))
    call(['arm-none-eabi-objcopy','-O','binary',path.with_suffix('.elf'),path.with_suffix('.bin')],out/(name+'.objcopy.log'))
    raw=path.with_suffix('.bin').read_bytes();hexfile(path.with_suffix('.hex'),raw)
    symbols={v[2]:int(v[0],16) for l in subprocess.check_output(['arm-none-eabi-nm',path.with_suffix('.elf')],text=True).splitlines() if len(v:=l.split())==3}
    return raw,symbols

def micro(out,kind):
    # Straight-line architectural loads interleaved with independent ALU work.
    if kind=='stream':
        lines=['stmdb sp!,{r4-r9}','mov r1,#0']
        for _ in range(16):
            for i in range(8):lines += [f'ldr r{2+i},[r0,#{4*i}]','add r1,r1,#1']
        lines += ['str r1,[r0,#64]','ldmia sp!,{r4-r9}','bx lr']
        expected=128
    else:
        lines=['mov r1,#0']+['ldr r2,[r0,#4]\nadd r1,r1,r2']*32+['str r1,[r0,#64]','bx lr']
        expected=32*0x101
    raw,_=assemble(out,kind+'-payload','.syntax unified\n.cpu arm920t\n.arm\n.section .vectors,"ax"\n.global _start\n_start:\n'+'\n'.join(lines)+'\n')
    c=dict(id=kind,module='synthetic',entry=0,iterations=1,operations=128 if kind=='stream' else 32,
           unit='loads',writes=[(0x80001000,sp.words([0x100+i for i in range(32)]))],
           regs=[0x80001000],strides=[0],checks=[(0x80001040,sp.words([expected]))],warmups=3 if kind=='dependency' else 2,samples=5)
    return c,raw

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--name',required=True);p.add_argument('--control',action='store_true')
    p.add_argument('--only',action='append',choices=['span','transpose','stream','dependency'])
    p.add_argument('--reuse-build',type=Path)
    p.add_argument('--legacy-transpose-layout',action='store_true',help='reproduce the earlier wrapper without added guard copies/checks')
    a=p.parse_args()
    assert re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,63}',a.name)
    out=ROOT/'build/sim/cpu-load-pipeline'/a.name;out.mkdir(parents=True,exist_ok=False)
    save(out/'result.json',dict(status='INCOMPLETE'))
    selected=set(a.only or ['span','transpose','stream','dependency'])
    source=support.snapshot(out/'source',BASE);overlay(out/'source',not a.control)
    source=support.source_manifest(out/'source',BASE,'5J-control' if a.control else '5J-P1-load')
    tb=(ROOT/'tests/cpu/spmark_payload/tb.v').read_text()
    tb=tb.replace('module bench;','module bench;\n`include "span.vh"\n`include "observe.vh"')
    tb=tb.replace('            if(retire && retire_pc==begin_pc) begin','            if(span_mode!=0)span_sample();\n            pipeline_sample();\n            if(retire && retire_pc==begin_pc) begin')
    tb=tb.replace('        if(!$value$plusargs("program=', '        if(!$value$plusargs("pipeline_trace=%d",j_trace))j_trace=0;\n        if(!$value$plusargs("span_mode=%d",span_mode))span_mode=0;\n        if(!$value$plusargs("inject_irq=%d",j_irq_enable))j_irq_enable=0;\n        if(!$value$plusargs("program=')
    tb=tb.replace('.irq(1\'b0)','.irq(j_irq)')
    (out/'tb.v').write_text(tb)
    span=(ROOT/'tests/cpu/super_monkey_ball/observe.vh').read_text()
    # The selected data owner can now be P1 before any P2 memory demand exists.
    span=span.replace('`SC.completion_next ?','j_select ?')
    (out/'span.vh').write_text(span);shutil.copyfile(HERE/'observe.vh',out/'observe.vh')
    hexfile(out/'empty.hex',bytes(4))
    docker=['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',str(ROOT)+':/work','-w','/work','--entrypoint']
    rtl=[out/'source/rtl/ngage_cpu.sv',out/'source/rtl/ngage_bram.v']
    for directory in ['rtl/arm','rtl/arm920']:rtl+=sorted(p for p in (out/'source'/directory).iterdir() if p.suffix in ['.v','.sv'])
    manifest=dict(source=source,variant='control' if a.control else 'candidate',
                  image_id=subprocess.check_output(['docker','image','inspect',IMAGE,'--format','{{.Id}}'],text=True).strip(),
                  fixtures={n:sha(out/n) for n in ['tb.v','span.vh','observe.vh']},
                  script_sha256=sha(Path(__file__)))
    save(out/'manifest.json',manifest)
    executable=out/'obj/Vbench'
    if a.reuse_build:
        previous=json.loads((ROOT/a.reuse_build/'manifest.json').read_text())
        assert all(previous[k]==manifest[k] for k in ['source','variant','image_id','fixtures'])
        executable=ROOT/previous['executable']
        assert sha(executable)==previous['executable_sha256']
    else:
        call(docker+['verilator',IMAGE,'--binary','--timing','--assert','-j','1','-Wno-fatal','-Wno-lint',
                 '-DNGAGE_RUNTIME_TRACE','-DBENCH_HAS_LINE',*(['-DPIPE_P1'] if not a.control else []),
                 '-GLINE_ENABLE=1','--top-module','bench','--Mdir',cp(out/'obj'),'-I'+cp(out),
                 '-I'+cp(out/'source/rtl/arm')]+[cp(f) for f in rtl]+[cp(out/'tb.v')],out/'build.log')
    manifest['executable']=str(executable.relative_to(ROOT))
    manifest['executable_sha256']=sha(executable);save(out/'manifest.json',manifest)
    print('Built',manifest['variant'],'one job',flush=True)
    rows=[];oracles={};programs={};negatives=[]
    cases=[]
    if 'span' in selected:
        code=smb.extract(ROOT/'tests/cpu/super_monkey_ball/local/SuperMonkeyBall.app')
        hexfile(out/'span-payload.hex',bytes(smb.ENTRY)+code+struct.pack('<I',0xe12fff1e))
        for pattern in ['forward','reverse']:
            f=smb.fixture(pattern);name='span-'+pattern;oracles[name]=smb.oracle(code,f)
            for bad in [False,True]:
                raw,symbols=assemble(out,name+('-wrong' if bad else ''),smb.assembly(f,bad))
                programs[name+('-wrong' if bad else '')]=dict(sha256=smb.digest(raw),symbols=symbols)
            cases.append(dict(id=name,payload='span-payload.hex',span=True,operations=smb.PIXELS))
    if 'transpose' in selected:
        c=next(c for c in sp.cases() if c['id']=='transpose4')
        guards=[(0x80000fe0,bytes((i*37+0x59)&255 for i in range(32))),
                (0x80001800,bytes((i*43+0xa3)&255 for i in range(32)))]
        if not a.legacy_transpose_layout:
            c['writes']+=guards;c['checks']+=guards
        raw=sp.image(ROOT/'tests/cpu/spmark_payload/local/3DTEST.DLL');hexfile(out/'transpose-payload.hex',bytes(raw))
        oracles[c['id']]=verify(c,raw,bytes(4))
        for bad in [False,True]:
            name=c['id']+('-wrong' if bad else '')
            raw,symbols=assemble(out,name,sp.assembly(c,bad));programs[name]=dict(sha256=smb.digest(raw),symbols=symbols)
        cases.append(dict(c,payload='transpose-payload.hex',span=False))
    for kind in ['stream','dependency']:
        if kind not in selected:continue
        c,raw=micro(out,kind);hexfile(out/(kind+'-payload.hex'),raw)
        oracles[kind]=verify(c,raw,bytes(4))
        for bad in [False,True]:
            name=kind+('-wrong' if bad else '')
            raw,symbols=assemble(out,name,sp.assembly(c,bad).replace('body_end:\n nop','body_end:\n nop\n .rept 16\n nop\n .endr'))
            programs[name]=dict(sha256=smb.digest(raw),symbols=symbols)
        cases.append(dict(c,payload=kind+'-payload.hex',span=False))
    save(out/'oracle.json',oracles);save(out/'programs.json',programs)
    for c in cases:
        for profile in ['0:0','2:9']:
            iw,dw=profile.split(':');observations=[]
            for bad in [False,True]:
                name=c['id']+('-wrong' if bad else '')
                for repeat in range(1 if bad else 2):
                    symbols=programs[name]['symbols']
                    options=['+program='+cp(out/(name+'.hex')),'+payload='+cp(out/c['payload']),'+firmware='+cp(out/'empty.hex'),
                             '+begin_pc='+format(1 if c['span'] else symbols['body_begin'],'x'),
                             '+end_pc='+format(2 if c['span'] else symbols['body_end'],'x'),
                             f'+span_mode={int(c["span"])}',f'+i_wait={iw}',f'+d_wait={dw}','+max_cycles=3000000',
                             '+ngage-compact-trace','+pipeline_trace='+str(int(not bad and profile=='0:0' and repeat==0))]
                    log=out/f'{name}-{iw}-{dw}-{repeat}.log'
                    rc=call(docker+[cp(executable),IMAGE,*options],log,bad)
                    text=log.read_text()
                    if bad:
                        assert rc!=0 and 'guest result check failed' in text
                        negatives.append(dict(case=c['id'],profile=profile,rejected=True));continue
                    prefix='SPAN_WINDOW ' if c['span'] else 'WINDOW '
                    windows=[dict((k,int(v)) for k,v in re.findall(r'(\w+)=(-?\d+)',l)) for l in text.splitlines() if l.startswith(prefix)]
                    warmups=2 if c['span'] else c['warmups'];count=warmups+5
                    assert len(windows)==count and f'RESULT windows={count} ' in text
                    if c['span']:
                        for w in windows[2:]:
                            assert w['instructions']==10240 and w['accepts']==w['ram_writes']==w['store_retires']==512
                            assert w['last_ram']<=w['last_store_retire']<=w['cycles']
                            assert sum(w[k] for k in ['read_stall','write_stall','load_lock','shift_lock','empty','other'])==w['cycles']
                    else:
                        ops=[dict((k,int(v)) for k,v in re.findall(r'(\w+)=(\d+)',l)) for l in text.splitlines() if l.startswith('PAYLOAD_WINDOW ')]
                        assert len(ops)==count and all(w['payload_retire_proxy']==oracles[c['id']]['payload_instructions'] and w['helper_retire_proxy']==0 for w in ops)
                    assert all(w['reads']==w['writes']==w['lines']==0 for w in windows[warmups:])
                    pipe=[dict((k,int(v)) for k,v in re.findall(r'(\w+)=(\d+)',l)) for l in text.splitlines() if l.startswith('PIPE_WINDOW ')]
                    assert len(pipe)==count
                    mutations=512 if c['span'] else 384 if c['id']=='transpose4' else 7 if c['id']=='stream' else 1
                    width=2 if c['span'] else 4
                    for w in pipe[warmups:]:
                        assert w['ram_mutations']==mutations and w['mutated_bytes']==mutations*width
                        assert w['store_acks']==mutations
                    observations.append(windows)
            assert observations[0]==observations[1]
            median=statistics.median(w['cycles'] for w in observations[0][warmups:])
            rows.append(dict(case=c['id'],profile=profile,cycles=median,cycles_per_operation=median/c['operations'],windows=observations[0],warmups=warmups,repeats_equal=2))
            print(c['id'],profile,median,'PASS',flush=True)
            save(out/'result.json',dict(status='INCOMPLETE',rows=rows))
    for n,h in source['files'].items():assert sha(out/'source'/n)==h
    save(out/'result.json',dict(status='PASS',manifest=manifest,programs=programs,oracle=oracles,rows=rows,negatives=negatives))
    print('PASS',out/'result.json',flush=True)

if __name__=='__main__':main()
