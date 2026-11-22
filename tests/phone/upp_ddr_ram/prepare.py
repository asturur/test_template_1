#!/usr/bin/env python3
"""Prepare UPP ownership and mixed ARM/PCM tests with current production RTL."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shlex
import shutil

HERE = Path(__file__).resolve().parent
OUT = Path('build/sim/upp-ddr-ram')
FIXTURE = Path('tests/phone/upp_ddr_ram')
REFERENCE = HERE.parent / 'upp_ddr3_impact'


def prepare_owner():
    maintained = Path('tests/phone/peripheral_response/run.sh').read_text().splitlines()[3]
    sources = [name for name in shlex.split(maintained)[6:] if name.startswith('rtl/')]
    command = ['iverilog', '-g2012', '-s', 'tb', '-o', str(OUT / 'peripherals.vvp'),
               *sources, str(FIXTURE / 'peer.v'), str(FIXTURE / 'peripherals_tb.v')]
    (OUT / 'peripherals.sh').write_text('set -eu\n' + shlex.join(command) +
                                       f'\nvvp {OUT}/peripherals.vvp > {OUT}/peripherals.log\n'
                                       f'grep "^PASS" {OUT}/peripherals.log\n')


def prepare_mixed():
    # Build the unchanged MMC media and pin harness from the retained replay.
    spec = importlib.util.spec_from_file_location('replay', REFERENCE / 'prepare.py')
    replay = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(replay)
    replay.OUT = OUT / 'mixed'
    replay.prepare_mixed(replay.SDRAM_MODEL)
    mixed = replay.OUT

    testbench = mixed / 'source/tests/phone/mmc_mister/tb.v'
    source = replay.replace(testbench.read_text(), (REFERENCE / 'mixed-observe.vh').read_text(),
                            (HERE / 'mixed.vh').read_text())
    source = replay.replace(source, 'report_upp_impact();', 'check_upp_ddr();')
    source = replay.replace(source, '.GAME_PCM(1)', '.GAME_PCM(1),.DDR_UPP_RAM(1)')
    source = replay.replace(source, '.cold_reset(cold),.dma_reset(dma_reset)', '''.cold_reset(cold),.dma_reset(dma_reset),
  .upp_ddr_req(ddr_req),.upp_ddr_we(ddr_we),.upp_ddr_addr(ddr_addr),
  .upp_ddr_wdata(ddr_wdata),.upp_ddr_be(ddr_be),.upp_ddr_ack(ddr_ack),.upp_ddr_rdata(ddr_rdata),
  .upp_ddr_clear(ddr_clear),.upp_ddr_clear_done(ddr_clear_done)''')
    testbench.write_text(source)

    stress = (mixed / 'stress.S').read_text()
    replay.build_guest('stress', replay.replace(stress, 'write_card_wait:',
                                                (HERE / 'atomic.S').read_text() + '\nwrite_card_wait:'))
    source_root = mixed / 'source'
    for frozen in sorted((source_root / 'rtl').rglob('*')):
        if frozen.is_file():
            shutil.copyfile(frozen.relative_to(source_root), frozen)
    hashes = {str(path.relative_to(source_root)): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in sorted(source_root.rglob('*')) if path.is_file()}
    hashes[str(FIXTURE / 'peer.v')] = hashlib.sha256((HERE / 'peer.v').read_bytes()).hexdigest()
    (mixed / 'source-hashes.json').write_text(json.dumps(hashes, indent=2) + '\n')
    build = mixed / 'build.sh'
    contents = build.read_text()
    build.write_text(replay.replace(contents, ' > ', f' {FIXTURE / "peer.v"} > '))


def main():
    if Path.cwd() != HERE.parents[2]:
        raise SystemExit('Run from the N-Gage project root')
    OUT.mkdir(parents=True, exist_ok=True)
    prepare_owner()
    prepare_mixed()


if __name__ == '__main__':
    main()
