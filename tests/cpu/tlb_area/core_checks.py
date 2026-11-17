#!/usr/bin/env python3
"""Use the maintained core peer's real FIQ/SWP/ordering stimuli on this CPU."""
import argparse,json,subprocess,re,hashlib,struct
from pathlib import Path
from setup import ROOT,HERE
p=argparse.ArgumentParser();p.add_argument('--build',type=Path,required=True);p.add_argument('--name',required=True);p.add_argument('--reuse-exe',type=Path);a=p.parse_args()
build=ROOT/a.build;out=ROOT/'build/sim/tlb-area'/a.name;out.mkdir(exist_ok=False);src=build/'source';manifest=json.loads((build/'manifest.json').read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def call(cmd,log):
    with (out/log).open('w') as f:r=subprocess.run([str(x) for x in cmd],cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
    assert r.returncode==0,str(out/log)
tb=(ROOT/'tests/cpu/core/test.sv').read_text().replace('module test;','module test;\nreg [4095:0] program_file;',1)
tb=tb.replace('$readmemh("build/sim/unit-core/program.hex",rom);','if (!$value$plusargs("program=%s",program_file))$fatal(1,"missing isolated program");\n  $readmemh(program_file,rom);',1);(out/'test.sv').write_text(tb)
docker=['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',str(ROOT)+':/work','-w','/work','--entrypoint'];cp=lambda p:'/work/'+str(p.relative_to(ROOT))
rtl=[src/'rtl/ngage_cpu.sv',src/'rtl/ngage_bram.v']
for d in ['arm','arm920']:rtl+=sorted((src/'rtl'/d).glob('*.sv'))
exe=out/'obj/Vtest'
if a.reuse_exe:
    exe=ROOT/a.reuse_exe
    assert sha(exe.parent.parent/'test.sv')==sha(out/'test.sv')
    for f,h in manifest['source']['files'].items():assert sha(src/f)==h
else:
    call(docker+['verilator','jotego/simulator:arm64','--binary','--timing','--assert','-j','1','-DNGAGE_RUNTIME_TRACE','-Wno-fatal','-Wno-lint','-I'+cp(src/'rtl/arm'),'--top-module','test','--Mdir',cp(out/'obj')]+[cp(f) for f in rtl]+[cp(out/'test.sv')],'build.log')
rows=[];programs={}
for case,args in [('fiq_store_return',['+fiq_privileged_store','+fiq_during_usrt']),('swp_mmu_abort',['+swp_mmu_abort']),('cache_tlb_write_order',['+tlb_order']),('icache_tlb_write_order',['+tlb_order_i']),('icache_prefetch_translated',['+check_prefetch'])]:
    asm=ROOT/'sim/programs'/(case+'.S');obj=out/(case+'.o');elf=out/(case+'.elf');binary=out/(case+'.bin')
    call(['arm-none-eabi-gcc','-c','-mcpu=arm920t','-marm',asm,'-o',obj],case+'-assemble.log');call(['arm-none-eabi-ld','-T',ROOT/'sim/programs/link.ld',obj,'-o',elf],case+'-link.log');call(['arm-none-eabi-objcopy','-O','binary',elf,binary],case+'-objcopy.log')
    raw=binary.read_bytes();raw+=bytes(-len(raw)%4);(out/(case+'.hex')).write_text(''.join(f'{v[0]:08x}\n' for v in struct.iter_unpack('<I',raw)))
    if case=='icache_prefetch_translated':
        symbols={v[2]:int(v[0],16) for l in subprocess.check_output(['arm-none-eabi-nm',elf],text=True).splitlines() if len(v:=l.split())==3};args+=['+icache_first='+format(symbols['icache_function_a'],'x')]
    programs[case]=dict(source_sha256=sha(asm),program_sha256=hashlib.sha256(raw).hexdigest(),stimulus=args)
    for delay in ([63,127] if case=='icache_tlb_write_order' else [15,31] if case=='cache_tlb_write_order' else [0,3]):
        log=f'{case}-{delay}.log';call(docker+[cp(exe),'jotego/simulator:arm64','+program='+cp(out/(case+'.hex')),'+ngage-compact-trace',f'+latency={delay}',*args],log)
        text=(out/log).read_text();events=[l for l in text.splitlines() if l.startswith(('PASS:','COUNTERS:'))];assert any(l.startswith('PASS:') for l in events)
        rows.append(dict(case=case,latency=delay,events=events));print(case,delay,events[-1],flush=True)
(out/'result.json').write_text(json.dumps(dict(status='PASS',source=manifest['source'],harness_sha256=sha(out/'test.sv'),executable_sha256=sha(exe),programs=programs,rows=rows),indent=2)+'\n')
