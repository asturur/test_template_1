"""Collect and check the offline v5 Disk Access results."""
import argparse
import json
from pathlib import Path
import re

from run import BASE

SIM = Path('build/sim/disk-access')
SYSTEM_HZ = 78000000


def load(name):
    result = json.loads((SIM / name / 'result.json').read_text())
    assert result['status'] == 'PASS'
    if 'baseline' in result:
        assert result['baseline'] == BASE
    return result


def ordered_groups(addresses):
    groups = []
    for slot, lba in addresses:
        if not groups or groups[-1][0] != slot or groups[-1][1][-1] + 1 != lba or len(groups[-1][1]) == 8:
            groups.append((slot, [lba]))
        else:
            groups[-1][1].append(lba)
    return groups


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--nor', default='nor-446-final')
    p.add_argument('--erase', default='nor-446-erase-final')
    p.add_argument('--guest', default='efile-actual-native')
    p.add_argument('--small', default='restore-512')
    p.add_argument('--large', default='restore-4k')
    p.add_argument('--mmc', default='mmc-39-final')
    p.add_argument('--hps', default='hps-restore-slot-4k')
    p.add_argument('--order', default='nor-host-order')
    p.add_argument('--cache', default='d2-cache-contract')
    p.add_argument('--ordering', default='nor-ordering')
    p.add_argument('--output', required=True, type=Path)
    args = p.parse_args()
    nor = load(args.nor)
    erased, = load(args.erase)['rows']
    guest = load(args.guest)
    assert guest['relative_drive'] == 'C:' and len(guest['rounds']) == 16
    phases = 'create_write', 'reopen_read', 'delete'
    for r in nor['rows']:
        r['guest_clocks'] = sum(r['intervals'][x]['clocks'] for x in phases)
        r['guest_files_per_second'] = round(25 * SYSTEM_HZ / r['guest_clocks'], 3)
        r['guest_payload_bytes_per_second'] = round(25 * 446 * SYSTEM_HZ / r['guest_clocks'], 1)
    for policy in ('scalar', 'update'):
        main = SIM / args.nor / f'{policy}-proxy'
        assert len(list(main.glob('run-*.log'))) == 6
        for log in main.glob('run-*.log'):
            assert 'PASS erase poll, B0, out-of-sector read, warm recovery and cold cancel' in log.read_text()
        assert 'PASS D2 raw NOR' in (SIM / args.ordering / f'{policy}-regression/run-None-0.log').read_text()
        assert 'PASS D2 flash cache' in (SIM / args.cache / policy / 'run.log').read_text()
    references = [r for r in nor['rows'] if r['wait'] == 8 and not r['autosave']]
    assert len(references) == 2
    assert erased['erase_line']
    for r in references:
        a, b = r['intervals'], erased['intervals']
        assert a['erase_order'] == b['erase_order']
        for counter in ('ddr_write', 'dirty_events', 'polls'):
            assert a['erase'][counter] == b['erase'][counter]
    mounts = load(args.small)['rows'] + load(args.large)['rows']
    for r in mounts:
        assert r['intervals']['mount'] == r['intervals']['remount']
        assert r['intervals']['mount']['bytes'] == 4259840
        assert r['intervals']['mount']['ddr_write'] == 532480
    for name, files in ((args.small,['0-short.log']), (args.large,['1-short.log','1-replace.log'])):
        for log in files:
            assert 'PASS restore fault left DDR untouched' in (SIM / name / log).read_text()
    mmc = load(args.mmc)
    hps = load(args.hps)
    for r in hps['rows']:
        assert 'PASS 4 KiB HPS slot 0/1' in (SIM/args.hps/f'run-{r["wait"]}.log').read_text()
    observed = (SIM / args.order / 'update-proxy/run-4096-0.log').read_text()
    ordered = [(int(slot),int(lba))
               for slot,lba in re.findall(r'^BACKING_WRITE slot=(\d+) lba=(\d+) active=0$', observed, re.M)][1:]
    assert len(ordered) == 27
    groups = ordered_groups(ordered)
    result = dict(status='PASS', baseline=BASE, system_hz=SYSTEM_HZ, fit_target_hz=104000000,
                  original_guest=guest, nor=nor, linked_erase=erased, restore=mounts, mmc=mmc,
                  hps_slots_0_1_4k=hps, ordered_save=dict(modeled_wait=4096, observed=ordered,
                  hypothetical_groups=groups, max_saved_start_delay=(len(ordered)-len(groups))*4096),
                  artifacts={key:str(SIM/value) for key,value in vars(args).items() if key!='output'})
    args.output.write_text(json.dumps(result, indent=2)+'\n')
    print(f'PASS {args.output}')


if __name__ == '__main__':
    main()
