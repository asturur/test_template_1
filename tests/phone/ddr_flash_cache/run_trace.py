"""Trace actual v5 CPU, NOR, refill and D2 service with a delayed DDR tail."""
import argparse
import glob
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
IMAGE = 'jotego/simulator:arm64'


def verify(log, program, early=False):
    events = []
    for line in log.splitlines():
        if line.startswith('D2_TRACE '):
            _, kind, cycle, address, *values = line.split()
            events.append((kind, int(cycle), int(address, 16), values))

    def at(kind, address):
        return [(cycle, values) for event, cycle, addr, values in events
                if event == kind and addr == address]

    def unique(kind, address):
        result = at(kind, address)
        assert len(result) == 1, (kind, hex(address), result)
        return result[0][0]

    def burst(base, address):
        start = unique('REQUEST', base)
        assert at('REQUEST', base)[0][1] == ['4']
        beats = []
        for offset in range(0, 32, 8):
            beat = base + offset
            beats.append(unique('RETURN', beat))
            raw = int.from_bytes(program[beat:beat + 8], 'little')
            assert int(at('RETURN', beat)[0][1][0], 16) == raw
        assert start < beats[0] < beats[1] < beats[2] < beats[3]
        assert beats[3] - beats[2] >= 48
        tag = unique('TAG', address)
        assert tag >= beats[3]
        return dict(request=start, physical_beats=beats, d2_tag=tag)

    scalar = []
    for index in range(8):
        base = 0x5000 + index * 64
        address = base + index * 4
        row = burst(base, address)
        admit = at('ADMIT', address)
        lookup = at('LOOKUP', address)
        words = at('WORD', address)
        ack = at('ACK', address)
        assert [values for _, values in lookup] == [['0', '0'], ['0', '1']]
        assert len(admit) == len(words) == len(ack) == 2
        expected = 0x5ACA4AB0 + index
        assert all(int(values[0], 16) == expected for _, values in words + ack)
        assert row['physical_beats'][index // 2] <= words[0][0] <= ack[0][0]
        if index // 2 < 3:
            assert ack[0][0] < row['physical_beats'][-1]
        assert admit[1][0] >= row['d2_tag']
        row.update(address=hex(address), admit=admit[0][0], first_data=words[0][0],
                   cpu_ack=ack[0][0], warm_admit=admit[1][0], warm_lookup=lookup[1][0],
                   warm_data=words[1][0], warm_cpu_ack=ack[1][0])
        scalar.append(row)

    instruction = []
    for index in range(8):
        base = 0x6000 + index * 64
        target = base + index * 4
        row = burst(base, base)
        line = [unique('LINE', base + offset) for offset in range(0, 32, 8)]
        words = [unique('ACK', base + offset) for offset in range(0, 32, 4)]
        expected_tail = ['0', '0', '0', '1']
        for offset in range(0, 32, 8):
            _, values = at('LINE', base + offset)[0]
            assert values[1] == expected_tail[offset // 8]
            assert int(values[0], 16) == int.from_bytes(program[base+offset:base+offset+8], 'little')
        for offset in range(0, 32, 4):
            _, values = at('ACK', base + offset)[0]
            assert int(values[0], 16) == int.from_bytes(program[base+offset:base+offset+4], 'little')
            assert int(values[1]) == 1
        assert words[0] < row['physical_beats'][-1]
        assert line[0] < row['physical_beats'][-1]
        if index < 6:
            assert words[index] < row['physical_beats'][-1]
        fetch = at('FETCH', target)
        executed = at('EXEC', target)
        retire = at('RETIRE', target)
        expected = int.from_bytes(program[target:target+4], 'little')
        assert len(retire) == 2 and len(fetch) >= 2
        assert all(int(values[0], 16) == expected for _, values in fetch)
        assert len(executed) >= 2 and all(int(values[0], 16) == 0x41 + index for _, values in executed)
        valid = unique('IVALID', target)
        assert valid >= words[-1]
        assert words[index] <= fetch[0][0] <= executed[0][0] <= retire[0][0]
        if early and index < 6:
            assert retire[0][0] < row['physical_beats'][-1], (index, row, retire)
        else:
            assert executed[0][0] >= row['physical_beats'][-1], (index, row, executed)
        row.update(target=hex(target), upstream_beats=line, cpu_word_acks=words,
                   i_cache_valid=valid, first_fetch=fetch[0][0], first_exec=executed[0][0],
                   first_retire=retire[0][0],
                   second_retire=retire[1][0])
        instruction.append(row)

    assert 'PASS D2 directed guest' in log
    return dict(scalar=scalar, instruction=instruction)


def run(capacity, divider, name=None, cpu_wrapper=None, netlist=None):
    out = ROOT / 'build/sim' / (name or f'd2-trace-{capacity}-mmc{divider}')
    out.mkdir(exist_ok=True)
    subprocess.run(['arm-none-eabi-gcc', '-c', '-mcpu=arm920t', '-marm',
                    HERE / 'trace_guest.S', '-o', out / 'guest.o'], check=True)
    subprocess.run(['arm-none-eabi-ld', '-T', ROOT / 'sim/programs/link.ld',
                    out / 'guest.o', '-o', out / 'guest.elf'], check=True)
    subprocess.run(['arm-none-eabi-objcopy', '-O', 'binary', out / 'guest.elf',
                    out / 'guest.bin'], check=True)
    program = (out / 'guest.bin').read_bytes()
    (out / 'core.bin').write_bytes(program.ljust(18612224, b'\0'))
    (out / 'extension.bin').write_bytes(bytes(2293760))
    (out / 'cdrive.bin').write_bytes(bytes(4194304))

    script = (ROOT / 'tests/phone/hardware_boot/run.sh').read_text()
    source_list = script.split('--Mdir build/sim/unit-hardware-boot/obj ', 1)[1].split(' > build/', 1)[0]
    sources = [f for token in source_list.split() for f in sorted(glob.glob(token))
               if not f.startswith(('rtl/arm/', 'rtl/arm920/'))]
    sources += ['rtl/arm9v2/arm925t_phone.v', *sorted(glob.glob('rtl/arm9v2/upstream/sim/stubs/*.sv')),
                'rtl/ngage_ddr_flash_adapter.v', 'rtl/ngage_ddr_flash_cache.v',
                'rtl/ngage_game_pcm.v', 'rtl/ngage_upp_dsp_pcm.v']
    if cpu_wrapper:
        sources[sources.index('rtl/ngage_cpu.sv')] = str(cpu_wrapper.resolve().relative_to(ROOT))
    if netlist:
        sources[sources.index('rtl/arm9v2/arm925t_phone.v')] = str(netlist.resolve().relative_to(ROOT))
    path = str(out.relative_to(ROOT))
    docker = ['docker', 'run', '--rm', '--pull=never', '--network', 'none',
              '--platform', 'linux/arm64', '-v', f'{ROOT}:/work', '-w', '/work', '--entrypoint']
    with (out / 'build.log').open('w') as log:
        subprocess.run(docker + ['verilator', IMAGE, '--binary', '--timing', '--assert', '-j', '2',
            '-DNGAGE_RUNTIME_TRACE', '-DNGAGE_ARM9V2', '-DNGAGE_PRODUCTION_DDR', '-DNGAGE_D2_DIRECTED',
            '-DNGAGE_POWERUP_NORMAL', '-Wno-fatal', '-Wno-lint', '-Irtl/arm', '--top-module', 'tb',
            '--Mdir', f'{path}/obj', '-GLINE_REFILL=1', '-GSYS_CLK_HZ=78000000', '-GTIMER_CLK_DIV=3',
            '-GNOS_TICK_HZ=64', '-GGAME_PCM=1', f'-GFLASH_CACHE_BYTES={capacity}',
            f'-GMMC_CLK_DIV={divider}', *sources], stdout=log, stderr=subprocess.STDOUT, check=True)
    with (out / 'run.log').open('w') as log:
        subprocess.run(docker + [f'/work/{path}/obj/Vtb', IMAGE, '+ngage-compact-trace', '+no-board-log',
            f'+core={path}/core.bin', f'+extension={path}/extension.bin', f'+cdrive={path}/cdrive.bin'],
            stdout=log, stderr=subprocess.STDOUT, check=True)
    log = (out / 'run.log').read_text()
    receipt = verify(log, program, early=cpu_wrapper is not None)
    (out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(next(line for line in log.splitlines() if line.startswith('PASS D2 directed guest')))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bytes', type=int, required=True, choices=(8192, 32768))
    parser.add_argument('--mmc-clk-div', type=int, default=4, choices=(2, 4))
    parser.add_argument('--name')
    parser.add_argument('--cpu-wrapper', type=Path)
    parser.add_argument('--arm9v2-netlist', type=Path)
    options = parser.parse_args()
    run(options.bytes, options.mmc_clk_div, options.name, options.cpu_wrapper, options.arm9v2_netlist)
