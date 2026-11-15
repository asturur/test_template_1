#!/usr/bin/env python3
"""Profile an accepted, frozen SPMark payload run without changing its harness/RTL."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess

from run import ROOT, IMAGE, command, cpath, save, sha, support
from workloads import cases

RUN_OUTPUT = None

BUCKETS = ['data_completion_wait', 'multiply_busy', 'load_dependency',
           'shift_dependency', 'redirect_event', 'decode_sequencing',
           'operand_queue_empty', 'advance_other']
STATES = ['IDLE', 'LOOKUP', 'READ_LINE', 'STORE_HIT', 'BYPASS', 'WAIT_REFILL',
          'MAINTAIN', 'MAINT_LOOKUP', 'BUFFER_STORE', 'WAIT_DRAIN', 'LOOKUP_WAIT',
          'MAINT_WAIT', 'STORE_COMMIT', 'LOOKUP_CAPTURE', 'MAINT_CAPTURE']


def fields(line):
    return {k: int(v) for k, v in re.findall(r'(\w+)=(\d+)', line)}


def parse_profile(text, observation):
    buckets, states, raw, pcs = {}, {}, {}, []
    for line in text.splitlines():
        if line.startswith('PROFILE_PC '):
            m = re.fullmatch(r'PROFILE_PC bucket=(\d+) pc=([0-9a-f]+) cycles=(\d+)', line)
            if not m:
                raise ValueError('bad PC histogram row')
            pcs.append(dict(bucket=int(m[1]), pc=int(m[2], 16), cycles=int(m[3])))
        elif line.startswith(('PROFILE_BUCKET ', 'PROFILE_STATE ', 'PROFILE_RAW ')):
            f = fields(line)
            index = f.pop('index')
            if line.startswith('PROFILE_BUCKET '):
                key = f.pop('bucket')
                if key in buckets.setdefault(index, {}):
                    raise ValueError('duplicate bucket')
                buckets[index][key] = f['cycles']
            elif line.startswith('PROFILE_STATE '):
                key = f.pop('state')
                if key in states.setdefault(index, {}):
                    raise ValueError('duplicate state')
                states[index][key] = f['cycles']
            else:
                if index in raw:
                    raise ValueError('duplicate raw profile')
                raw[index] = f
    if set(raw) != set(range(7)) or set(buckets) != set(raw) or set(states) != set(raw):
        raise ValueError('profile window set differs')
    windows = []
    for i, window in enumerate(observation['windows']):
        b, s, r = buckets[i], states[i], raw[i]
        if set(b) != set(range(8)) or set(s) != set(range(15)):
            raise ValueError('incomplete profile categories')
        if sum(b.values()) != window['cycles'] or r['cycles'] != window['cycles']:
            raise ValueError('profile cycles differ from measured window')
        if r['retire'] != window['retire_proxy'] or sum(s.values()) != b[0]:
            raise ValueError('profile retirement/cache-state accounting differs')
        if r['read_wait'] + r['write_wait'] != b[0]:
            raise ValueError('data direction accounting differs')
        windows.append(dict(buckets={BUCKETS[k]: b[k] for k in range(8)},
                            cache_states={STATES[k]: s[k] for k in range(15)}, raw=r))
    if len({(p['bucket'], p['pc']) for p in pcs}) != len(pcs):
        raise ValueError('duplicate PC histogram entry')
    for bucket in range(5):
        expected = sum((w['raw']['retire'] if bucket == 4 else
                        w['buckets'][BUCKETS[bucket]]) for w in windows[2:])
        if sum(p['cycles'] for p in pcs if p['bucket'] == bucket) != expected:
            raise ValueError('PC histogram does not reconcile with scored windows')
    return dict(windows=windows, pcs=pcs)


def report(out, result):
    lines = ['# SPMark cycle profile', '',
             'Priority attribution of blocking signals, not additive recoverable cycle loss.',
             'Warm-up windows excluded. Observer must match every original raw counter.', '',
             '| Workload | I:D | Data wait | Multiply | Load dependency | Shift dependency | Redirect event | Decode sequence | Empty operand queue | Advance/other |',
             '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
    for row in result['rows']:
        windows = row['profile']['windows'][2:]
        cycles = sum(w['raw']['cycles'] for w in windows)
        counts = {k: sum(w['buckets'][k] for w in windows) for k in BUCKETS}
        row['scored_cycles'] = cycles
        row['bucket_percentages'] = {k: 100*v/cycles for k, v in counts.items()}
        row['cache_state_percent_of_all_cycles'] = {k: 100*sum(w['cache_states'][k] for w in windows)/cycles for k in STATES}
        lines.append('| '+row['case']+' | '+row['memory_profile']+' | '+' | '.join(f'{100*counts[k]/cycles:.2f}%' for k in BUCKETS)+' |')
    lines += ['', 'Buckets take priority in the displayed order. Retirement and raw bus/fetch activity can overlap them.',
              'Redirect counts measure event edges, not the full redirect/recovery penalty. Empty-queue time is not yet attributed to a cause.',
              'Data-cache state occupancy separates translation/handshake, tag/line lookup, store commit and external/refill activity.',
              'Top-PC counts identify the actual held demand/operand owner; they are not generic time assigned to the last retired instruction.',
              'Synthetic backing model; no physical SDRAM timing, LCD/MMC traffic or Symbian scheduler.', '']
    for row in result['rows']:
        lines += ['## '+row['case']+' / '+row['memory_profile'], '', '| Held owner | PC | Cycles across five samples | Instruction |', '| --- | --- | ---: | --- |']
        for bucket in range(4):
            ranked=sorted((p for p in row['profile']['pcs'] if p['bucket']==bucket),key=lambda p:-p['cycles'])[:5]
            for p in ranked:
                lines.append(f'| {BUCKETS[bucket]} | {p["pc"]:08X} | {p["cycles"]:,} | {p.get("instruction", "")} |')
        lines += ['', 'Data-cache states (% of all measured clocks): '+', '.join(f'{k} {v:.2f}%' for k,v in sorted(row['cache_state_percent_of_all_cycles'].items(),key=lambda kv:-kv[1]) if v), '']
    (out/'report.md').write_text('\n'.join(lines)+'\n')


def decode_pcs(out, row, program_hex, payload_hex, firmware_hex):
    def raw(path):
        return b''.join(int(word,16).to_bytes(4,'little') for word in path.read_text().split())
    images = [(0, raw(program_hex)), (0x10000000, raw(payload_hex)), (0x50300000, raw(firmware_hex))]
    pcs=sorted({p['pc'] for p in row['profile']['pcs']})
    words=[]
    for pc in pcs:
        for base, data in images:
            if base <= pc < base+len(data):
                words.append(data[pc-base:pc-base+4]); break
        else: raise ValueError(f'unmapped disassembly PC {pc:x}')
    path=out/'hot-instructions.bin';path.write_bytes(b''.join(words))
    text=subprocess.check_output(['arm-none-eabi-objdump','-D','-b','binary','-m','arm',str(path)],text=True)
    decoded={}
    for line in text.splitlines():
        m=re.match(r'\s*([0-9a-f]+):\s+[0-9a-f]{8}\s+(.*)',line)
        if m: decoded[pcs[int(m[1],16)//4]]=m[2].strip()
    for p in row['profile']['pcs']: p['instruction']=decoded.get(p['pc'],'')


def input_hashes(base, manifest, selected):
    def raw_hex(path):
        return b''.join(int(word,16).to_bytes(4,'little') for word in path.read_text().split())
    names={'firmware.hex'}
    for c in selected:
        binary=(base/(c['id']+'.bin')).read_bytes()
        if sha(binary)!=manifest['programs'][c['id']]['sha256']:
            raise ValueError('base guest binary changed')
        padded=binary+bytes((-len(binary))%4)
        if raw_hex(base/(c['id']+'.hex'))!=padded:
            raise ValueError('program hex differs from qualified binary')
        payload=c['module']+'.hex'
        if sha(raw_hex(base/payload))!=manifest['payload_sha256'][c['module']]:
            raise ValueError('payload hex differs from qualified payload')
        names.update([c['id']+'.hex',c['id']+'.bin',payload])
    return {name:sha((base/name).read_bytes()) for name in sorted(names)}


def main():
    global RUN_OUTPUT
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base',type=Path,required=True)
    parser.add_argument('--name',required=True)
    parser.add_argument('--case',action='append',default=[])
    parser.add_argument('--profile',action='append',default=[])
    parser.add_argument('--repeat',type=int,default=2)
    args=parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+',args.name) or args.repeat<1:
        parser.error('name must be a simple unique name; repeat must be positive')
    base=args.base.resolve();base.relative_to(ROOT)
    accepted=json.loads((base/'result.json').read_text());manifest=accepted['manifest']
    if accepted['status']!='PASS':raise ValueError('base did not pass')
    if manifest['format'] != 'spmark-payload-line16-v1':raise ValueError('unsupported benchmark format')
    enum_text=(base/'source/rtl/arm920/cache_access.sv').read_text()
    enum=re.search(r'typedef enum logic \[3:0\] \{(.*?)\} state_t;',enum_text,re.S)
    if not enum or [x.strip() for x in enum[1].split(',')] != STATES:
        raise ValueError('data-cache state encoding changed; adapt profiler labels')
    profiles=args.profile or ['0:0']
    if not set(profiles)<=set(manifest['profiles']):raise ValueError('profile absent from base')
    selected=[c for c in cases() if not args.case or c['id'] in args.case]
    if args.case and set(args.case)!={c['id'] for c in selected}:raise ValueError('unknown case')
    original={(r['case'],r['profile']):r for r in accepted['rows']}
    out=ROOT/'build/sim/spmark-profile'/args.name
    out.mkdir(parents=True,exist_ok=False)
    RUN_OUTPUT = out
    result=dict(status='INCOMPLETE',base=str(base.relative_to(ROOT)),rows=[],
                source_id=manifest['source']['source_id'],meaning='blocking-signal occupancy; not additive causal loss',repeat=args.repeat)
    result['base_result_sha256']=sha((base/'result.json').read_bytes())
    result['input_sha256']=input_hashes(base,manifest,selected)
    save(out/'result.json',result)
    for name,h in manifest['source']['files'].items():
        if sha((base/'source'/name).read_bytes())!=h:raise ValueError('frozen base source changed: '+name)
    if sha((base/'tb.v').read_bytes())!=manifest['harness_sha256']:raise ValueError('base harness changed')
    shutil.copytree(base/'source',out/'source')
    observer=Path(__file__).with_name('profile.vh');shutil.copyfile(observer,out/'profile.vh')
    tb=(base/'tb.v').read_text()
    for needle,replacement in [
        ('    initial begin\n', '    `include "profile.vh"\n\n    initial begin\n'),
        ('            if(retire && retire_pc==begin_pc)', '            if(start_cycle>=0)prof_sample();\n            if(retire && retire_pc==begin_pc)'),
        ('start_helper_ops=helper_ops;', 'start_helper_ops=helper_ops;prof_begin();'),
        ('                windows=windows+1;', '                prof_end();\n                windows=windows+1;'),
        ('                        $display("RESULT ', '                        prof_dump();\n                        $display("RESULT '),
    ]:
        if tb.count(needle)!=1:raise ValueError('base harness injection seam changed: '+needle)
        tb=tb.replace(needle,replacement)
    (out/'tb.v').write_text(tb)
    image_id=subprocess.check_output(['docker','image','inspect',IMAGE,'--format','{{.Id}}'],text=True).strip()
    if image_id!=manifest['image_id']:raise ValueError('simulator image differs from accepted run')
    docker=['docker','run','--rm','--pull=never','--network','none','--platform','linux/arm64','-v',str(ROOT)+':/work','-w','/work','--entrypoint']
    source=out/'source';rtl=[source/'rtl/ngage_cpu.sv',source/'rtl/ngage_bram.v']
    for directory in ['rtl/arm','rtl/arm920']:
        rtl+=sorted(p for p in (source/directory).iterdir() if p.suffix in ['.v','.sv'])
    command(docker+['verilator',IMAGE,'--binary','--timing','--assert','-j','4','-Wno-fatal','-Wno-lint',
                    '-DNGAGE_RUNTIME_TRACE','-DBENCH_HAS_LINE','-GLINE_ENABLE=1','--top-module','bench',
                    '--Mdir',cpath(out/'obj'),'-I'+cpath(source/'rtl/arm'),'-I'+cpath(out)]+[cpath(p) for p in rtl]+[cpath(out/'tb.v')],out/'build.log')
    bench=support()
    try:
        for c in selected:
            if sha((base/(c['id']+'.bin')).read_bytes())!=manifest['programs'][c['id']]['sha256']:raise ValueError('base guest changed')
            symbols=manifest['programs'][c['id']]
            for profile in profiles:
                iw,dw=profile.split(':');observations=[]
                for repeat in range(args.repeat):
                    log=out/f'{c["id"]}-{iw}-{dw}-{repeat}.log'
                    command(docker+[cpath(out/'obj/Vbench'),IMAGE,'+program='+cpath(base/(c['id']+'.hex')),
                        '+payload='+cpath(base/(c['module']+'.hex')),'+firmware='+cpath(base/'firmware.hex'),
                        f'+begin_pc={symbols["body_begin"]:x}',f'+end_pc={symbols["body_end"]:x}',f'+i_wait={iw}',f'+d_wait={dw}',
                        '+max_cycles=30000000','+ngage-compact-trace'],log)
                    text=log.read_text();observation=bench.parse_log(text,c)
                    reference=original[c['id'],profile]
                    payload_windows=[fields(line) for line in text.splitlines() if line.startswith('PAYLOAD_WINDOW ')]
                    if payload_windows != reference['payload_windows']:
                        raise ValueError('observer changed payload/helper retirement counters')
                    for key,value in observation.items():
                        if reference[key]!=value:raise ValueError('observer changed raw counter: '+key)
                    observations.append(parse_profile(text,observation))
                if any(p!=observations[0] for p in observations[1:]):raise ValueError('profile repeats differ')
                row=dict(case=c['id'],memory_profile=profile,original_counters_identical=True,profile=observations[0])
                decode_pcs(out,row,base/(c['id']+'.hex'),base/(c['module']+'.hex'),base/'firmware.hex')
                result['rows'].append(row);save(out/'result.json',result)
                print('PASS:',c['id'],profile,'profile reconciles; observer leaves all original counters unchanged',flush=True)
        if input_hashes(base,manifest,selected)!=result['input_sha256']:
            raise ValueError('input changed during profiling')
        for name,h in manifest['source']['files'].items():
            if sha((out/'source'/name).read_bytes())!=h:
                raise ValueError('frozen profiling source changed')
        result['status']='PASS'
        result['observer_sha256']=sha(observer.read_bytes());result['harness_sha256']=sha((out/'tb.v').read_bytes())
        result['executable_sha256']=sha((out/'obj/Vbench').read_bytes());result['image_id']=image_id
        report(out,result)
    except Exception:
        result['status']='FAIL';raise
    finally:save(out/'result.json',result)
    print('PASS:',out/'report.md',flush=True)


if __name__=='__main__':
    try:
        main()
    except Exception as exc:
        if RUN_OUTPUT is not None:
            path = RUN_OUTPUT/'result.json'
            result = json.loads(path.read_text()) if path.exists() else {}
            result.update(status='FAIL', error=str(exc))
            save(path, result)
        raise
