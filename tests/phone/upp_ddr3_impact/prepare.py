#!/usr/bin/env python3
"""Prepare retained v5 UPP RAM simulations without changing production inputs."""
import argparse
import hashlib
import json
from pathlib import Path
import shlex
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BASE = '53b707b'
OUT = Path('build/sim/upp-ddr3-impact/mixed')
MMC = Path('tests/phone/mmc_mister')
BOOT = Path('tests/phone/hardware_boot')
SDRAM_MODEL = Path('build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v')
SDRAM_MODEL_SHA = '61af63207be722deaf2b97a892ee76cbb26e8cb21013db6b60a5566f6985952b'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def source(path):
    return subprocess.check_output(['git', 'show', f'{BASE}:{path}'], cwd=ROOT)


def replace(text, before, after):
    if text.count(before) != 1:
        raise ValueError(f'Expected exactly one match for {before!r}')
    return text.replace(before, after)


def patched_fixture(name):
    patch = HERE / f'mixed-{name}.patch'
    with tempfile.TemporaryDirectory(dir=OUT) as folder:
        original = Path(folder) / name
        updated = original.with_suffix('.patched')
        original.write_bytes(source(MMC / name))
        subprocess.run(['patch', '-s', '-i', str(patch), '-o', updated, original], check=True)
        return updated.read_text()


def build_guest(stem, text):
    assembly = OUT / f'{stem}.S'
    obj = assembly.with_suffix('.o')
    elf = assembly.with_suffix('.elf')
    binary = assembly.with_suffix('.bin')
    assembly.write_text(text)
    commands = (
        ['arm-none-eabi-gcc', '-c', '-mcpu=arm920t', '-marm', assembly, '-o', obj],
        ['arm-none-eabi-ld', '-T', 'sim/programs/link.ld', obj, '-o', elf],
        ['arm-none-eabi-objcopy', '-O', 'binary', elf, binary],
    )
    for command in commands:
        subprocess.run(command, check=True)
    words = binary.read_bytes()
    assert len(words) % 4 == 0 and len(words) <= 8192
    assembly.with_suffix('.hex').write_text(''.join(
        f'{int.from_bytes(words[i:i+4], "little"):08x}\n' for i in range(0, len(words), 4)
    ))


def prepare_mixed(model_path):
    model = model_path.read_bytes()
    if sha(model) != SDRAM_MODEL_SHA:
        raise ValueError('Expected the adapted Micron SDRAM pin model used for the retained mixed replay')
    OUT.mkdir(parents=True, exist_ok=True)
    guest = patched_fixture('program.S')
    build_guest('program', guest)
    build_guest('stress', replace(
        guest, 'write_card_wait:', (HERE / 'stress.S').read_text() + '\nwrite_card_wait:',
    ))

    # Reuse the in-tree, synthetic MMC media generator. The larger write
    # block exponent is the same override as the original writable probe.
    card = source(MMC / 'prepare.py').decode()
    card = replace(card, "root / 'build/sim/unit-mmc-mister'", f"root / '{OUT}'")
    card = replace(card, "(1 << 77)", "(1 << 77) | (9 << 22)")
    exec(compile(card, str(MMC / 'prepare.py'), 'exec'), {'__file__': str((MMC / 'prepare.py').resolve())})

    reference = 'build/sim/v5-104-wb-request-banks-native-mixed-parent-arm9v2-div3-pcm-lcd'
    bench = patched_fixture('tb.v').replace(reference, str(OUT))
    bench = replace(bench, 'endmodule', (HERE / 'mixed-observe.vh').read_text() + '\nendmodule')
    bench = replace(
        bench, f'  $readmemh("{OUT}/program.hex",rom);',
        f'  if ($test$plusargs("upp_stress")) $readmemh("{OUT}/stress.hex",rom);\n'
        f'  else $readmemh("{OUT}/program.hex",rom);',
    )
    bench = replace(bench, "      if(saved_sa==25'h100)begin",
                    "      if(saved_sa==25'h100)begin\n       report_upp_impact();")

    upp_path = Path('rtl/ngage_upp_peripherals.v')
    upp = source(upp_path).decode()
    upload_bram = '    ngage_bram_be #(\n        .AW(14)\n    ) upload_ram'
    upp = replace(upp, upload_bram, '    wire local_ready;\n' +
                  (HERE / 'raw_wait.vh').read_text() + '\n' + upload_bram)
    upp = replace(upp, '    wire local_ready = ', '    assign local_ready = ')
    upp = replace(upp, '        gpio_data = gpr_q & wmask;',
                  '        gpio_data = (model_selected ? model_read_data : gpr_q) & wmask;')
    upp = replace(upp, '                   (!ram_read || (rd_vld && rd_adr == a));',
                  '                   (!ram_read || (rd_vld && rd_adr == a)) && model_ready;')
    for selected in ['upload_selected', 'nosmem_selected']:
        upp = replace(upp, f'(({selected} && ram_write) ? sel',
                      f'(({selected} && ram_write && !model_selected) ? sel')

    run_script = source(MMC / 'run.sh').decode()
    verilator_args = run_script.split("-c '", 1)[1].split(' > build/sim/unit-mmc-mister/build.log', 1)[0]
    patterns = [arg for arg in shlex.split(verilator_args) if arg.endswith(('.v', '.sv'))]
    names = [path for pattern in patterns for path in sorted(ROOT.glob(pattern))]
    names += [ROOT / path for path in (
        'rtl/ngage_game_pcm.v', 'rtl/ngage_upp_dsp_pcm.v', 'rtl/arm9v2/arm925t_phone.v',
        'rtl/arm9v2/upstream/sim/stubs/altdpram.sv', 'rtl/arm9v2/upstream/sim/stubs/altsyncram.sv',
        'rtl/ngage_sdram_stream.v', 'rtl/ngage_sdram_line_mux.v', 'rtl/sdram/ngage_sdram_scheduler.v',
        'rtl/ngage_sdram_clock.v', 'tests/phone/sdram/ddio_model.v',
    )]
    names += [ROOT / SDRAM_MODEL, *sorted((ROOT / 'rtl/arm').glob('*.svh'))]
    override = {MMC / 'tb.v': bench.encode(), upp_path: upp.encode(), SDRAM_MODEL: model}
    files = []
    hashes = {}
    for path in names:
        name = path.relative_to(ROOT)
        data = override[name] if name in override else source(name)
        dest = OUT / 'source' / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        hashes[str(name)] = sha(data)
        if dest.suffix != '.svh':
            files.append(str(dest))
    (OUT / 'source-hashes.json').write_text(json.dumps(hashes, indent=2) + '\n')
    command = [
        'verilator', '--binary', '--timing', '--assert', '-j', '4', '-Wno-fatal', '-Wno-lint',
        '-I' + str(OUT / 'source/rtl/arm'), '--top-module', 'tb', '--Mdir', str(OUT / 'obj'),
        '-GMMC_CLK_DIV=3', '-GTIMER_CLK_DIV=4', '-GNOS_TICK_HZ=64',
        '-DNGAGE_ARM9V2', '-DNGAGE_BLOCK_WRITEBACK', *files,
    ]
    (OUT / 'build.sh').write_text('set -eu\n' + shlex.join(command) + f' > {OUT}/build.log 2>&1\n')

    reset_script = source(Path('tests/phone/peripheral_response/run.sh')).decode().splitlines()[3]
    reset_sources = [
        OUT / 'source' / name for name in shlex.split(reset_script)[6:] if name.startswith('rtl/')
    ]
    reset_command = ['iverilog', '-g2012', '-s', 'tb', '-o', str(OUT / 'reset.vvp'),
                     *map(str, reset_sources), str((HERE / 'reset_tb.v').relative_to(ROOT))]
    (OUT / 'reset.sh').write_text(
        'set -eu\n' + shlex.join(reset_command) + '\n'
        'for region in 0 1 2 3; do\n'
        f'    log="{OUT}/reset-$region.log"\n'
        f'    vvp {OUT}/reset.vvp +upp_regions="$region" +upp_read_extra=48 +upp_write_extra=24 > "$log"\n'
        '    grep "^PASS" "$log"\n'
        'done\n'
    )


def prepare_boot():
    scratch = Path('scratch/upp-ddr3-impact')
    scratch.mkdir(parents=True, exist_ok=True)
    bench = (BOOT / 'tb.v').read_text()
    generated_bench = scratch / 'boot_tb.v'
    generated_bench.write_text(replace(bench, 'endmodule', (HERE / 'observe.vh').read_text() + '\nendmodule'))
    runner = (BOOT / 'run-logo.py').read_text()
    runner = replace(runner, 'Path(__file__).resolve().parents[3]', 'Path.cwd()')
    runner = replace(runner, "assert sources and 'tests/phone/hardware_boot/tb.v' in sources",
                     f"sources[sources.index('tests/phone/hardware_boot/tb.v')] = '{generated_bench}'")
    runner = replace(runner, "b'PROGRESS ',", "b'PROGRESS ',b'UPP_ACCESS ',")
    (scratch / 'run-logo.py').write_text(runner)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('fixture', choices=['mixed', 'boot'])
    parser.add_argument('--sdram-model', type=Path, default=SDRAM_MODEL)
    arguments = parser.parse_args()
    if Path.cwd() != ROOT:
        parser.error('Run from the N-Gage project root')
    if arguments.fixture == 'mixed':
        prepare_mixed(arguments.sdram_model)
    else:
        prepare_boot()


if __name__ == '__main__':
    main()
