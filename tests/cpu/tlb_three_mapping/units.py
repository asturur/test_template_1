"""Run maintained MMU units on the frozen pair and reject a stale-slot grant."""
import argparse
import json

from build import CPU, DOCKER, IMAGE, OUT, command, cpath, replace, save, sha

CASES = ('tlb64_bank', 'tlb_attributes', 'tlb_bus_gate', 'tlb_lookup_owner',
         'tlb_permission_reuse', 'tlb_two_mapping')


def run(out, builds):
    out.mkdir(parents=True, exist_ok=False)
    rows = []
    for build in builds:
        manifest = json.loads((build/'manifest.json').read_text())
        src = build/'source'
        assert all(sha(src/name)==sha256 for name,sha256 in manifest['source']['files'].items())
        candidate = manifest['candidate']
        tlb = src/'rtl/arm920/tlb.sv'
        base = [src/'rtl/ngage_bram.v', src/'rtl/arm920/tlb_bank.sv']
        command(DOCKER+['iverilog',IMAGE,'-g2001','-s','arm920_tlb','-tnull']
                + (['-P','arm920_tlb.THIRD_MAPPING=1'] if candidate else [])
                +[cpath(path) for path in base+[tlb]], out/(build.name+'-v2001.log'))
        for name in CASES+(('stale-third-grant',) if candidate else ()):
            negative = name=='stale-third-grant'
            fixture = CPU/('tlb_two_mapping' if negative else name)/'test.sv'
            selected = tlb
            if negative:
                selected = out/'tlb-stale-negative.sv'
                # Leave the oldest grant alive across a main-table fill only.
                selected.write_text(replace(tlb.read_text(),
                                             '        third_valid <= 0;\n      end else if (token_valid',
                                             '        if (!bank_fill) third_valid <= 0;\n      end else if (token_valid'))
            if name=='tlb_bus_gate':
                sources = [src/'rtl/arm920/tlb_bus_gate.sv']
            else:
                sources = base+([] if name=='tlb64_bank' else [selected])
            flags = ['-DTEST_THIRD_MAPPING'] if candidate and fixture.parent.name=='tlb_two_mapping' else []
            obj = out/f'{build.name}-{name}'
            command(DOCKER+['verilator',IMAGE,'--binary','--timing','--assert','-j','2','-Wno-fatal','-Wno-lint',
                            '--top-module','test','--Mdir',cpath(obj),*flags]
                    +[cpath(path) for path in sources+[fixture]], out/(obj.name+'-build.log'))
            log = out/(obj.name+'.log')
            rc = command(DOCKER+[cpath(obj/'Vtest'),IMAGE],log,negative=negative)
            lines = log.read_text().splitlines()
            if negative:
                evidence = [line for line in lines if 'stale third-slot grant after main-table replacement' in line]
                assert rc and len(evidence)==1
            else:
                evidence = [line for line in lines if line.startswith('PASS')]
                assert evidence, log
            rows.append(dict(build=build.name,case=name,evidence=evidence,negative_rejected=negative))
            print(build.name,name,*evidence,flush=True)
    save(out/'result.json',dict(status='PASS',test_sha256=sha(CPU/'tlb_two_mapping/test.sv'),rows=rows))


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name',required=True)
    parser.add_argument('--build',action='append',required=True)
    args = parser.parse_args()
    run(OUT/args.name,[OUT/name for name in args.build])
