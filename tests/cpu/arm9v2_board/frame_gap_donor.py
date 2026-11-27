"""Replay the checked frame proxies on the pinned donor CPU and memory RTL."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import statistics
import subprocess
import sys

from frame_gap_early import swap
from payload_clocks import DOCKER, FIRMWARE, HERE, IMAGE, OUT, ROOT, ROM_SHA
from payload_clocks import arrange_flash, container_path, digest, find, qualified_inputs

DONOR_FILES = (
    'rtl/cpu/arm925t_gen.v', 'sim/stubs/altsyncram.sv', 'sim/stubs/altdpram.sv',
    'rtl/upp/ngage_mem.sv', 'rtl/upp/upp_bus.sv', 'rtl/upp/wb_arb2.sv',
    'rtl/mem/ddram_flash.sv', 'rtl/mem/sdram.sv', 'rtl/mem/bram32.sv',
    'rtl/board/sdp_ram.sv', 'rtl/board/nor_flash.sv',
)


def donor_section_xor(cpu):
    # Same folded index as v5, on the D-side instance. Fetch stays direct.
    cpu = swap(cpu, ".CHECK_WALK(1'b1),", ".CHECK_WALK(1'b1), .SECTION_INDEX_XOR(1'b1),")
    cpu = swap(cpu, "parameter [0:0] CHECK_WALK = 1'b0;",
               "parameter [0:0] CHECK_WALK = 1'b0;\n    parameter SECTION_INDEX_XOR = 1'b0;")
    cpu = swap(cpu, '.i_raddr(i_address_nxt[(20 + $clog2(SECTION_TLB_ENTRIES)) - 1:20]),',
               '.i_raddr(section_index(i_address_nxt[31:20])),')
    cpu = swap(cpu, '.i_waddr(tlb_address[(20 + $clog2(SECTION_TLB_ENTRIES)) - 1:20]),',
               '.i_waddr(section_index(tlb_address[31:20])),')
    anchor = 'zap_mem_inv_block #(\n\t\t.WIDTH(44 - $clog2(SECTION_TLB_ENTRIES)),'
    function = '''localparam integer SIW = $clog2(SECTION_TLB_ENTRIES);
    function [SIW-1:0] section_index;
        input [11:0] section_page;
        reg [11:0] high_page;
        begin
            high_page = section_page >> SIW;
            section_index = section_page[SIW-1:0];
            if (SECTION_INDEX_XOR) section_index = section_index ^ high_page[SIW-1:0];
        end
    endfunction
    '''
    return swap(cpu, anchor, function + anchor)


def sparse_flash(path, out, wrapper, case, original):
    staged = out.with_suffix('.bin')
    arrange_flash(staged, wrapper, case, original, None)
    data = staged.read_bytes()
    spans = ((0, len(wrapper)), (0x300000, 0x100000), (case['payload_at'], len(case['payload'])))
    with path.open('w') as stream:
        for start, count in spans:
            print(f'@{start // 8:x}', file=stream)
            for offset in range(start, start + count, 8):
                print(data[offset:offset + 8][::-1].hex(), file=stream)
    return digest(data)


def measure(out, case, mode):
    name = case['name']
    log_path = out / f'{name}-{mode}.log'
    options = []
    if mode == '0':
        options.append('+trace=' + container_path(out / f'{name}-requests.txt'))
    exe = out / 'obj/Vframe_gap_donor'
    with log_path.open('w') as log:
        result = subprocess.run(DOCKER + [container_path(exe), IMAGE,
            '+flash=' + container_path(out / f'{name}-{mode == "wrong"}.hex'),
            f'+begin_pc={case["begin"]:x}', f'+end_pc={case["end"]:x}',
            f'+payload_base={case["payload_base"]:x}', f'+helper_base={case["helper_base"]:x}',
            *options], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    output = log_path.read_text()
    if mode == 'wrong':
        assert result.returncode and 'Guest output check rejected payload' in output, log_path
        return None
    assert result.returncode == 0 and 'PASS donor checked payload' in output, log_path
    windows = find(log_path, 'DONOR_WINDOW ')
    assert len(windows) == 7, log_path
    for window, expected in zip(windows, case['windows'], strict=True):
        assert window['payload_ops'] == expected['payload_retire_proxy'], (log_path, window, expected)
        assert window['helper_ops'] == expected['helper_retire_proxy'], (log_path, window, expected)
    return windows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name', required=True)
    parser.add_argument('--revision', default='ff6dcff')
    parser.add_argument('--donor', type=Path, default=Path('/Users/andreabogazzi/develop/ngage2'))
    parser.add_argument('--sdram-model', type=Path, required=True)
    parser.add_argument('--case', action='append', choices=('fill16_frame','sega-scan'))
    parser.add_argument('--scalar-writeback', action='store_true')
    parser.add_argument('--dcache-16k', action='store_true')
    parser.add_argument('--section-xor', action='store_true')
    args = parser.parse_args()
    if args.name != Path(args.name).name or args.name in ('.','..'):
        parser.error('The run name must be a single new path component')
    out = OUT / 'payload-clocks' / args.name
    out.mkdir(parents=True)
    source = out / 'source'
    source.mkdir()
    revision = subprocess.check_output(['git', '-C', args.donor, 'rev-parse', args.revision + '^{commit}'], text=True).strip()
    paths = []
    hashes = {}
    for path in DONOR_FILES:
        data = subprocess.check_output(['git', '-C', args.donor, 'show', f'{revision}:{path}'])
        if path == 'rtl/cpu/arm925t_gen.v':
            cpu = data.decode()
            if args.dcache_16k:
                cpu = swap(cpu, 'localparam signed [31:0] DCACHE_SIZE = 8192;',
                           'localparam signed [31:0] DCACHE_SIZE = 16384;')
            if args.section_xor:
                cpu = donor_section_xor(cpu)
            data = cpu.encode()
        target = source / Path(path).name
        target.write_bytes(data)
        paths.append(container_path(target))
        hashes[path] = digest(data)
    for path in (args.sdram_model, HERE / 'frame_gap_donor.sv', ROOT / 'rtl/ngage_sdram_clock.v',
                 ROOT / 'tests/phone/sdram/ddio_model.v'):
        target = source / path.name
        target.write_bytes(path.read_bytes())
        paths.append(container_path(target))
        hashes[path.name] = digest(target.read_bytes())
    cmd = DOCKER + ['verilator', IMAGE, '--binary', '--timing', '--assert', '-j', '3',
        '-DNGAGE_RUNTIME_TRACE', '-Wno-fatal', '-Wno-lint', '--top-module', 'frame_gap_donor',
        '--Mdir', container_path(out / 'obj'), f'-GSCALAR_WRITEBACK={int(args.scalar_writeback)}', *paths]
    original = (FIRMWARE / 'core.bin').read_bytes()
    assert digest(original) == ROM_SHA
    cases = [case for case in qualified_inputs() if case['name'] in (args.case or ('fill16_frame','sega-scan'))]
    assert cases
    result = dict(status='RUNNING', revision=revision, source=hashes, rom_sha256=ROM_SHA,
                  scalar_writeback=args.scalar_writeback, dcache_16k=args.dcache_16k,
                  section_xor=args.section_xor, rows=[])
    with (out / 'build.log').open('w') as log, ThreadPoolExecutor(max_workers=3) as pool:
        process = pool.submit(subprocess.run, cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
        prepared = {}
        for case in cases:
            name = case['name']
            prepared[name] = {key: sparse_flash(out / f'{name}-{key == "bad"}.hex',
                                               out / f'{name}-{key}.bin', case[key], case, original)
                              for key in ('good','bad')}
        process.result()
        for case in cases:
            name = case['name']
            jobs = [pool.submit(measure, out, case, mode) for mode in ('0','1','wrong')]
            first, repeat, bad = (job.result() for job in jobs)
            assert first == repeat and bad is None
            clocks = statistics.median(w['cycles'] for w in first[2:])
            result['rows'].append(dict(case=name, median_clocks=clocks, windows=first,
                                       flash_sha256=prepared[name], wrong_output_rejected=True))
            print(name, clocks, 'clocks', flush=True)
            (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    result['status'] = 'PASS'
    (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
