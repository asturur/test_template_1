#!/usr/bin/env python3
"""Annotate a sim instruction trace with romsyms library!ordinal(+off) names,
or full function names when NGAGE_DEFS points at the SDK ordinal .def files.

    symtrace.py <trace.tsv> [--defs DIR] [--from CYC] [--to CYC] [--mods]

Uses the Pocket core's romsyms (~/develop/n-gage/tools/ngvm). Without defs it
prints library!ordN+off; with the Series 60 1st Ed SDK defs it prints real
names (euser!CActiveScheduler::Start, etc.). (made with Claude 2026-10-29)
"""
import argparse, os, signal, sys
NGVM = os.path.expanduser('~/develop/n-gage/tools/ngvm')
sys.path.insert(0, NGVM)
ROM = 'build/firmware/nem4-factory/digest-probe-core-nosstub/SYM.ROM'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('trace')
    ap.add_argument('--rom', default=ROM)
    ap.add_argument('--defs', default=os.environ.get('NGAGE_DEFS', '/nonexistent'))
    ap.add_argument('--from', dest='lo', type=int, default=0)
    ap.add_argument('--to', dest='hi', type=int, default=1 << 62)
    ap.add_argument('--mods', action='store_true',
                    help='collapse to function-boundary transitions only')
    a = ap.parse_args()
    signal.signal(signal.SIGALRM, lambda *x: (_ for _ in ()).throw(TimeoutError()))
    signal.alarm(90)
    import romsyms
    s = romsyms.Syms(a.rom, defs_dir=a.defs)
    signal.alarm(0)
    last = None
    for line in open(a.trace):
        p = line.rstrip('\n').split('\t', 1)
        if len(p) < 2 or not p[0].isdigit():
            continue
        cyc = int(p[0])
        if cyc < a.lo or cyc > a.hi:
            continue
        try:
            pc = int(p[1][:8], 16)
        except ValueError:
            continue
        nm = s.name(pc)
        if a.mods:
            fn = nm.split('+')[0]
            if fn != last:
                print(f'{cyc}\t{nm}')
                last = fn
        else:
            print(f'{cyc}\t{pc:08x}\t{nm}')


if __name__ == '__main__':
    main()
