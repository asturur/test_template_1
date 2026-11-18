"""Run the checked experiment matrix against an existing frozen build."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import re
import statistics
import struct
import subprocess
import sys
from pathlib import Path

from build import CPU, DOCKER, HERE, IMAGE, OUT, ROOT, command, cpath, digest, replace, save, sha
from source import load, support
import game
import sega_scan

sys.path.insert(0, str(CPU/'spmark_payload'))
import workloads as sp
from oracle import verify
smb = load('monkey_ball_workload', CPU/'super_monkey_ball/workload.py')
jpeg = load('jpeg_workload', CPU/'cache_probe_retime/jpeg_workload.py')

PROFILES = ('0:0', '2:9')
SMALL_PA = {
    0x80001000:0x0a014000, 0x80003000:0x0a00b000,
    0x80004000:0x0a00c000, 0x80008000:0x0a008000,
}


def hexfile(path, raw):
    raw += bytes(-len(raw)%4)
    path.write_text(''.join(f'{word:08x}\n' for (word,) in struct.iter_unpack('<I', raw)))


def assemble(out, name, text):
    src, obj, elf, binary = (out/(name+suffix) for suffix in ('.S','.o','.elf','.bin'))
    src.write_text(text)
    command(['arm-none-eabi-gcc','-c','-mcpu=arm920t','-marm',src,'-o',obj], out/(name+'.as.log'))
    command(['arm-none-eabi-ld','-T',ROOT/'sim/programs/link.ld',obj,'-o',elf], out/(name+'.ld.log'))
    command(['arm-none-eabi-objcopy','-O','binary',elf,binary], out/(name+'.bin.log'))
    table = subprocess.check_output(['arm-none-eabi-nm', elf], text=True).splitlines()
    symbols = {fields[2]:int(fields[0],16) for line in table if len(fields:=line.split())==3}
    raw = binary.read_bytes()
    assert len(raw)<0x40000
    return raw, symbols


def small_pages(asm):
    old = ' ldr r0,=0x0a000c0e\n ldr r5,=0x2000\n str r0,[r4,r5]'
    lines = [' ldr r0,=0x0a01b001', ' ldr r5,=0x2000', ' str r0,[r4,r5]',
             ' ldr r5,=0x0a01b000']
    for va, pa in SMALL_PA.items():
        lines.extend((f' ldr r0,={pa|0xffe}', f' str r0,[r5,#{((va>>12)&255)*4}]'))
    return replace(asm, old, '\n'.join(lines))


def stream(out):
    # Same checked 5L stream as cpu_load_pipeline/bench.py: 128 identical loads
    # with independent ADDs, through the original call and return wrapper.
    lines = ['stmdb sp!,{r4-r9}', 'mov r1,#0']
    for _ in range(16):
        for i in range(8):
            lines.extend((f'ldr r{2+i},[r0,#{4*i}]', 'add r1,r1,#1'))
    lines.extend(('str r1,[r0,#64]', 'ldmia sp!,{r4-r9}', 'bx lr'))
    raw, _ = assemble(out,'stream-payload',
                      '.syntax unified\n.cpu arm920t\n.arm\n.section .vectors,"ax"\n'
                      '.global _start\n_start:\n'+'\n'.join(lines))
    case = dict(id='arm-stream', module='synthetic', entry=0, iterations=1,
                operations=128, unit='loads', regs=[0x80001000], strides=[0],
                writes=[(0x80001000,sp.words([0x100+i for i in range(32)]))],
                checks=[(0x80001040,sp.words([128]))], warmups=2, samples=5)
    return case, raw


def prepare(out, suites):
    evaluated = {}

    def add(case, suite, oracle, program, payload, firmware=b'\0'*4,
            payload_base=sp.PAYLOAD_BASE, span=False):
        name = case['id']
        args = [f'+payload_base={payload_base:x}']
        if span:
            args.append('+span_mode=1')
        if name=='arm-stream':
            args.append('+stream_mode=1')
        info = dict(case, suite=suite, oracle=oracle, span=span, options=args, variants={})
        for bad in (False, True):
            variant = name+('-wrong' if bad else '')
            raw, symbols = assemble(out, variant, program(bad))
            payload_file = out/(variant+'-payload.hex')
            data = payload(symbols) if callable(payload) else payload
            hexfile(payload_file, data)
            hexfile(out/(variant+'.hex'), raw)
            begin = 1 if span else symbols['body_begin']
            end = 2 if span else symbols['body_end']
            info['variants'][bad] = dict(name=variant, begin=begin, end=end,
                                          payload_sha256=digest(data), program_sha256=digest(raw))
        fwname = 'firmware-'+digest(firmware)[:12]+'.hex'
        if not (out/fwname).exists():
            hexfile(out/fwname, firmware)
        info['firmware'] = fwname
        evaluated[name] = info

    if {'spmark', 'jpeg', 'scan'} & suites:
        rom = (ROOT/'build/firmware/nem4-factory/core.bin').read_bytes()
        assert digest(rom)==sp.ROM_SHA==jpeg.ROM_SHA
        fw = rom[0x300000:0x400000]
    if 'spmark' in suites:
        local = CPU/'spmark_payload/local'
        modules = {name:sp.image(local/name) for name in sp.EXPECTED_IMAGES}
        iat, ordinal, target, exports = 0x199a0, 1514, 0x503a2f6c, 0x503cab7c
        assert struct.unpack_from('<I',modules['libGLES_CM.dll'],iat)[0]==ordinal
        assert struct.unpack_from('<I',rom,exports-0x50000000+(ordinal-1)*4)[0]==target
        struct.pack_into('<I',modules['libGLES_CM.dll'],iat,target)
        for case in sp.cases():
            data = modules[case['module']]
            add(case,'spmark',verify(case,data,fw),lambda bad:sp.assembly(case,bad),data,fw)
    if 'jpeg' in suites:
        for case in jpeg.cases():
            def program(bad):
                asm = sp.assembly(case,bad)
                asm = replace(asm,'ldr r0,=0x10000c0e','ldr r0,=0x50500c0e')
                asm = replace(asm,'str r0,[r4,#0x400]','ldr r5,=0x1414\n str r0,[r4,r5]')
                return replace(asm, f'ldr r12,={sp.PAYLOAD_BASE+case["entry"]}',
                               f'ldr r12,={jpeg.BASE+case["entry"]}')
            add(case,'jpeg',jpeg.oracle(case,rom),program,rom[0x500000:0x600000],fw,jpeg.BASE)
    if 'monkey' in suites:
        code = smb.extract(CPU/'super_monkey_ball/local/SuperMonkeyBall.app')
        payload = bytes(smb.ENTRY)+code+struct.pack('<I',0xe12fff1e)
        for pattern in ('forward', 'reverse'):
            fixture = smb.fixture(pattern)
            expected = smb.oracle(code, fixture)
            for small in (False,True):
                name = f'monkey-{pattern}'+('-small' if small else '')
                case = dict(id=name, operations=smb.PIXELS, unit='pixels',
                            warmups=2, samples=5, stores=smb.PIXELS)
                def program(bad):
                    asm = smb.assembly(fixture,bad)
                    return small_pages(asm) if small else asm
                add(case, 'monkey', expected, program, payload, span=True)
    if 'games' in suites:
        originals = {name:game.image(name) for name in game.IMAGES}
        for name,(key,entry,last) in game.LOOPS.items():
            case = game.fixture(name)
            code = originals[key][entry:last+4]
            def payload(symbols):
                return bytes(entry)+code+struct.pack('<II',0xe51ff004,symbols['loop_return'])
            add(case,'games',game.verify(case,code,entry,last),
                lambda bad:game.assembly(case,entry,bad,sp.assembly),payload)
    if 'scan' in suites:
        case, code = sega_scan.fixture(rom)
        fw505 = rom[0x500000:0x600000]
        add(case,'scan',sega_scan.verify(case,code,fw505),
            lambda bad:sega_scan.assembly(case,bad,sp.assembly),
            lambda syms:sega_scan.payload(code,syms),fw505)
    if 'stream' in suites:
        case, data = stream(out)
        add(case,'stream',verify(case,data,bytes(4)),
            lambda bad:replace(sp.assembly(case,bad), 'body_end:\n nop',
                               'body_end:\n nop\n .rept 16\n nop\n .endr'),data)
    return evaluated


def events(text,prefix,base=10):
    return [{key:int(value,10 if key=='index' else base) for key,value in re.findall(r'(\w+)=(-?\w+)',line)}
            for line in text.splitlines() if line.startswith(prefix+' ')]


def parse(text,case):
    expected = case['warmups']+case['samples']
    tlb = events(text,'MAP_WINDOW')
    effects = events(text,'MAP_EFFECT',16)
    total, = events(text,'MAP_TOTAL')
    assert [w['index'] for w in tlb]==[w['index'] for w in effects]==list(range(expected))
    oracle = case['oracle']
    if case['span']:
        windows = events(text,'SPAN_WINDOW')
        result, = events(text,'RESULT')
        assert len(windows)==result['windows']==expected
        assert all(w['instructions']==oracle['instructions'] for w in windows)
        for w in windows[case['warmups']:]:
            assert w['accepts']==w['ram_writes']==w['store_retires']==oracle['stores']
            assert w['reads']==w['writes']==w['lines']==0
            assert w['last_ram']<=w['last_store_retire']<=w['cycles']
    else:
        windows = support.parse_log(text,case)['windows']
        retired = events(text,'PAYLOAD_WINDOW')
        assert len(retired)==expected
        for r in retired:
            if case['suite'] in {'spmark','stream'}:
                assert r['payload_retire_proxy']==oracle['payload_instructions']
                assert r['helper_retire_proxy']==oracle['helper_instructions']
            elif case['suite']=='jpeg':
                assert r['payload_retire_proxy']+r['helper_retire_proxy']==oracle['instructions']
            elif case['suite']=='scan':
                assert r['payload_retire_proxy']==oracle['payload_instructions']+1
                assert r['helper_retire_proxy']==oracle['helper_instructions']
            else:
                assert r['payload_retire_proxy']==oracle['instructions']+1, (case['id'],r,oracle)
                assert r['helper_retire_proxy']==0
        for w,r in zip(windows,retired):
            w.update(r)
    for w,t,e in zip(windows,tlb,effects):
        assert w['index']==t['index']==e['index']
        if case['suite'] in {'monkey','games'}:
            assert t['stores']==oracle['stores'], (case['id'],t,oracle['stores'])
        w.update(t, pc_hash=f'{e["pc"]:016x}', store_hash=f'{e["stores"]:016x}')
    thumb = events(text,'THUMB_WINDOW')
    if thumb:
        assert [w['index'] for w in thumb]==list(range(expected))
        for w,t in zip(windows,thumb):
            w.update(thumb={k:v for k,v in t.items() if k!='index'})
    return dict(windows=windows, total=total)


def replica(out,exe,case,profile,bad,repeat):
    iw,dw = profile.split(':')
    variant = case['variants'][bad]
    name = variant['name']
    log = out/f'{name}-{iw}-{dw}-{repeat}.log'
    trace_mode = 2 if case['span'] else 1
    trace = trace_mode if not bad and profile=="0:0" and repeat==0 else 0
    limit = 90000000 if case['suite']=='scan' else 30000000
    rc = command(DOCKER+[cpath(exe),IMAGE,
              '+program='+cpath(out/(name+'.hex')),
              '+payload='+cpath(out/(name+'-payload.hex')),
              '+firmware='+cpath(out/case['firmware']),
              f'+begin_pc={variant["begin"]:x}',f'+end_pc={variant["end"]:x}',
              f'+i_wait={iw}',f'+d_wait={dw}',f'+max_cycles={limit}',
              '+ngage-compact-trace',f'+mapping_trace={trace}',*case['options']],
              log,negative=bad)
    text = log.read_text()
    if bad:
        assert rc and 'guest result check failed' in text, log
        return None
    try:
        return parse(text,case)
    except (ValueError,AssertionError) as error:
        raise ValueError(f'{log}: {error}') from error


def measure(out,exe,manifest,name,case,profile,parallel_repeats):
    legs = ((False,0),(False,1),(True,0))
    if parallel_repeats:
        with ThreadPoolExecutor(max_workers=len(legs)) as pool:
            jobs = [pool.submit(replica,out,exe,case,profile,bad,repeat) for bad,repeat in legs]
            repeats = [job.result() for job in jobs]
    else:
        repeats = [replica(out,exe,case,profile,bad,repeat) for bad,repeat in legs]
    assert repeats[0]==repeats[1], (name,profile,'repeat differs')
    windows = repeats[0]['windows']
    scored = windows[case['warmups']:]
    cycles = statistics.median(w['cycles'] for w in scored)
    if name in ('monkey-forward','monkey-reverse') and not manifest['candidate']:
        assert cycles=={'monkey-forward':34995,'monkey-reverse':34920}[name], (name,profile,cycles)
    if name=='arm-stream':
        assert all(w['starts']==w['start_clocks']==224 for w in scored), scored
    return dict(case=name,suite=case['suite'],profile=profile,unit=case['unit'],
                operations=case['operations'],median=cycles,cycles_per_unit=cycles/case['operations'],
                **repeats[0], oracle=case['oracle'], variants=list(case['variants'].values()),
                warmups=case['warmups'], repeats_equal=2, wrong_output_rejected=True)


def run(build, out, suites, workers=1, parallel_repeats=False):
    manifest = json.loads((build/'manifest.json').read_text())
    assert manifest.get('full_scan',False)==(suites=={'scan'})
    exe = build/'obj/Vbench'
    assert sha(exe)==manifest['executable_sha256']
    assert all(sha(build/name)==h for name,h in manifest['harness'].items())
    assert all(sha(build/'source'/name)==h for name,h in manifest['source']['files'].items())
    assert manifest['image']==subprocess.check_output(['docker','image','inspect',IMAGE,'--format','{{.Id}}'],text=True).strip()
    out.mkdir(parents=True,exist_ok=False)
    report = dict(status='INCOMPLETE',build=manifest,rows=[])
    save(out/'result.json',report)
    cases = prepare(out,suites)
    with ThreadPoolExecutor(max_workers=workers) as pool:
        jobs = [pool.submit(measure,out,exe,manifest,name,case,profile,parallel_repeats)
                for name,case in cases.items() for profile in PROFILES]
        for job in as_completed(jobs):
            row = job.result()
            report['rows'].append(row)
            save(out/'result.json',report)
            print('PASS',row['case'],row['profile'],row['median'],'clocks',flush=True)
    order = {name:i for i,name in enumerate(cases)}
    report['rows'].sort(key=lambda row:(order[row['case']],row['profile']))
    report.update(status='PASS')
    save(out/'result.json',report)


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name',required=True)
    parser.add_argument('--build',required=True)
    parser.add_argument('--suite',action='append',choices=['spmark','jpeg','monkey','games','stream','scan'])
    parser.add_argument('--parallel-repeats',action='store_true')
    parser.add_argument('--workers',type=int,default=1)
    args = parser.parse_args()
    assert 1<=args.workers<=6
    for name in (args.name,args.build):
        assert Path(name).name==name and name not in ('.','..')
    run(OUT/args.build,OUT/args.name,set(args.suite or ('spmark','jpeg','monkey','games','stream')),args.workers,args.parallel_repeats)
