"""Exercise real halfword credits, store-data dependency, aborts and uncached ordering."""
import argparse
import json

from experiment import HERE, freeze, peer
from run import PROFILES, assemble, hexfile
from source import compiler_sources

FIRMWARE_SETUP = HERE.parent / 'thumb_early_load/directed.S'
STORES = {
    'warm_low': (0x80001010, 3, 0xbeefbeef),
    'warm_high': (0x80001012, 12, 0xcafecafe),
    'load_data': (0x80001012, 12, 0xef12ef12),
    'uncached_high': (0x82012002, 12, 0xef12ef12),
    'older_before_abort': (0x80001010, 3, 0x55665566),
}
FAULTS = {'unmapped': (0x90000000, 5), 'denied': (0x81002000, 13), 'misaligned': (0x80001011, 1)}
FORBIDDEN = ('forbidden_translation', 'forbidden_permission', 'forbidden_alignment')


def guest():
    prefix = FIRMWARE_SETUP.read_text().split(' ldr sp,=', 1)[0]
    prefix = peer.replace(prefix, ' mcr p15,0,r4,c2,c0,0', ''' ldr r0,=0x0a00000e
 ldr r5,=0x2040
 str r0,[r4,r5]
 ldr r0,=0x0a000c02
 ldr r5,=0x2080
 str r0,[r4,r5]
 mcr p15,0,r4,c2,c0,0''')
    prefix = peer.replace(prefix, ' orr r0,r0,#5', ' bic r0,r0,#0x300\n orr r0,r0,#5')
    return prefix + (HERE / 'store_safety.S').read_text()


def audit(text, symbols, candidate):
    traffic = [dict(token.split('=') for token in line.split()[1:])
               for line in text.splitlines() if line.startswith('SAFE_HALF ')]
    by_pc = {label: [e for e in traffic if int(e['pc'], 16) == symbols[label]]
             for label in (*STORES, *FAULTS, *FORBIDDEN)}
    for label, expected in STORES.items():
        r, = [e for e in by_pc[label] if e['accept'] == '1']
        assert tuple(int(r[k], 16) for k in ('va', 'mask', 'data')) == expected
        assert sum(e['ack']=='1' for e in by_pc[label]) == 1
        if label == 'uncached_high' or not candidate:
            assert r['credit'] == '0'
        else:
            assert r['credit'] == '1', (label, r)
    for label in FAULTS:
        assert by_pc[label] and all(e['accept'] == e['credit'] == '0' for e in by_pc[label]), label
    assert not any(by_pc[label] for label in FORBIDDEN)
    faults = [dict(token.split('=') for token in line.split()[1:])
              for line in text.splitlines() if line.startswith('SAFE_FAULT ')]
    assert [(int(r['pc'], 16), int(r['far'], 16), int(r['fsr'], 16)) for r in faults] == [
        (symbols[name], far, fsr) for name, (far, fsr) in FAULTS.items()
    ], faults
    bus, = [line for line in text.splitlines() if line.startswith('SAFE_BUS ')]
    assert bus == 'SAFE_BUS va=0a012000 mask=c data=ef12ef12'
    result, = [line for line in text.splitlines() if line.startswith('RESULT ')]
    return dict(stores={label: by_pc[label] for label in STORES}, bus=bus, faults=faults, result=result)


def run(out, candidate):
    out.mkdir(parents=True, exist_ok=False)
    source = out / 'source'
    manifest = freeze(source, candidate=candidate, redirect_lookahead=True)
    harness = (peer.CPU / 'spmark_payload/tb.v').read_text()
    harness = peer.replace(harness, 'module bench;',
                            'module bench;\n' + (HERE / 'store_safety.vh').read_text())
    tb = out / 'tb.v'
    tb.write_text(harness)
    exe = out / 'obj/Vbench'
    peer.command(peer.DOCKER + ['verilator', peer.IMAGE, '--binary', '--timing', '--assert',
        '-j', '2', '-Wno-fatal', '-Wno-lint', '-DNGAGE_RUNTIME_TRACE',
        '-DBENCH_HAS_LINE', '-GLINE_ENABLE=1', '--top-module', 'bench', '--Mdir', peer.cpath(exe.parent),
        '-I'+peer.cpath(source / 'rtl/arm')]
        + [peer.cpath(p) for p in compiler_sources(source)] + [peer.cpath(tb)], out / 'build.log')
    (program, symbols) = assemble(out, 'directed', guest())
    hexfile(out / 'directed.hex', program)
    hexfile(out / 'empty.hex', bytes(4))
    rows = []
    for profile in (*PROFILES, '0:97'):
        iw, dw = profile.split(':')
        repeats = []
        for n in range(2):
            log = out / f'{iw}-{dw}-{n}.log'
            peer.command(peer.DOCKER + [peer.cpath(exe), peer.IMAGE, '+program='+peer.cpath(out/'directed.hex'),
                '+payload='+peer.cpath(out/'empty.hex'), '+firmware='+peer.cpath(out/'empty.hex'),
                '+begin_pc=1', '+end_pc=2', f'+i_wait={iw}', f'+d_wait={dw}', '+max_cycles=1000000'], log)
            repeats.append(audit(log.read_text(), symbols, candidate))
        assert repeats[0] == repeats[1]
        rows.append(dict(profile=profile, **repeats[0]))
        print('PASS', out.name, profile, flush=True)
    peer.save(out / 'result.json', dict(status='PASS', source=manifest, program=peer.digest(program), rows=rows))


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('name')
    p.add_argument('--candidate', action='store_true')
    args = p.parse_args()
    run(peer.OUT / args.name, args.candidate)
