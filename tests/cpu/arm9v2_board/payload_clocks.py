"""Replay qualified fixed-work guests on the full phone RTL at both NOS/MMC rates."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import glob
import hashlib
import json
from pathlib import Path
import re
import statistics
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'build/sim'
HERE = Path(__file__).resolve().parent
IMAGE = 'jotego/simulator:arm64'
FIRMWARE = ROOT / 'build/firmware/nem4-factory'
DOCKER = ['docker', 'run', '--rm', '--pull=never', '--network', 'none', '--platform', 'linux/arm64',
          '-v', f'{ROOT}:/work', '-w', '/work', '--entrypoint']
sys.path.insert(0, str(ROOT / 'tools'))
from build_virtual_sim import encode16, rules
sys.path.insert(0, str(ROOT / 'tests/cpu/spmark_payload'))
from workloads import ROM_SHA, cases as spmark_cases
from frame_gap_early import swap


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def container_path(path):
    return '/work/' + str(path.relative_to(ROOT))


def record(line):
    return {key: int(value) for key, value in re.findall(r'(\w+)=(\d+)', line)}


def find(path, prefix):
    return [record(line) for line in path.read_text().splitlines() if line.startswith(prefix)]


def binary_hex(path):
    return b''.join(int(line, 16).to_bytes(4, 'little') for line in path.read_text().splitlines())


def qualified_inputs():
    modules = {case['id']: case['module'] for case in spmark_cases()}
    names = ('spmark-payload/v5-32b-spmark-01', 'arm9v2/v5-32b-games-01',
             'arm9v2/v5-32b-scan-01', 'jpeg-payload/v5-32b-jpeg-01')
    for group, parent in enumerate(names):
        archive = OUT / parent
        accepted = json.loads((archive / 'result.json').read_text())
        assert accepted['status'] == 'PASS'
        for row in accepted['rows']:
            if row['profile'] != '0:0' or row.get('cpu', 'arm9v2') != 'arm9v2':
                continue
            name = row['case']
            if group in (0, 3):
                manifest = accepted['manifest']
                prefix = name if group == 0 else 'jpeg'
                guest = manifest['programs'][prefix]
                negative = prefix + '-wrong-output'
                assert digest((archive / f'{negative}.bin').read_bytes()) == manifest['programs'][negative]['sha256']
                windows = find(archive / f'{prefix}-0-0-0.log', 'PAYLOAD_WINDOW ')
            else:
                guest = row['guest']
                prefix = name
                negative = prefix + '-wrong'
                windows = find(archive / f'arm9v2-{prefix}-0-0-0.log', 'PAYLOAD_WINDOW ')
            assert len(windows) == 7
            raw = (archive / f'{prefix}.bin').read_bytes()
            assert digest(raw) == (guest['program_sha256'] if 'program_sha256' in guest else guest['sha256'])
            payload_at = 0x00400000
            payload_base, helper_base = 0x10000000, 0x50300000
            if group == 0:
                module = modules[name]
                payload = binary_hex(archive / f'{module}.hex')
                assert digest(payload) == manifest['payload_sha256'][module]
            elif group == 3:
                payload = binary_hex(archive / 'payload.hex')
                payload_at, payload_base = 0x00500000, 0x50500000
            else:
                payload = binary_hex(archive / f'{prefix}-payload.hex')
                assert digest(payload) == guest['payload_sha256']
                if group == 2:
                    helper_base = 0x50500000
            begin = guest['begin_pc'] if 'begin_pc' in guest else guest['body_begin']
            end = guest['end_pc'] if 'end_pc' in guest else guest['body_end']
            yield dict(name=name, good=raw, bad=(archive / f'{negative}.bin').read_bytes(),
                       payload=payload, payload_at=payload_at, payload_base=payload_base,
                       helper_base=helper_base, scan=group == 2, begin=begin, end=end, windows=windows)


def arrange_flash(path, wrapper, case, original, rule):
    # VA stays linked to the original code. Give the payload, EUSER/FbsCli and
    # result mailbox physical pages the production flash/RAM decoder owns.
    remaps = [(0xf0000c02, 0x0a100c02), (0x50300c0e, 0x00300c0e)]
    if case['payload_base'] == 0x10000000:
        remaps.append((0x10000c0e, 0x00400c0e))
    else:
        remaps.append((0x50500c0e, 0x00500c0e))
    wrapper = bytearray(wrapper)
    for old, new in remaps:
        before = struct.pack('<I', old)
        assert wrapper.count(before) == 1 and wrapper.index(before) % 4 == 0
        wrapper = wrapper.replace(before, struct.pack('<I', new))
    if rule is not None:
        for addr in range(0xa000, len(wrapper), 2):
            plain, = struct.unpack_from('<H', wrapper, addr)
            struct.pack_into('<H', wrapper, addr, encode16(plain, addr, rule))
    with path.open('wb') as f:
        f.truncate(len(original))
        f.write(wrapper)
        # The full-screen native scan aliases the FbsCli megabyte at PA 003.
        helper = 0x00500000 if case['scan'] else 0x00300000
        f.seek(0x00300000)
        f.write(original[helper:helper + 0x100000])
        f.seek(case['payload_at'])
        f.write(case['payload'])


def compile_phone(out, divider, hz, arm9v2_netlist, flash_cache_bytes, sdram_model, cpu_wrapper, posted_writes, interleave, pin_waits, handoff, donor_sdram, stream_sdram, block_writeback):
    source = ROOT / 'tests/phone/hardware_boot/run.sh'
    raw = source.read_text().split('--Mdir build/sim/unit-hardware-boot/obj ', 1)[1].split(' > build/', 1)[0]
    rtl = [name for pattern in raw.split() for name in sorted(glob.glob(pattern))
           if not name.startswith(('rtl/arm/', 'rtl/arm920/')) and name != 'tests/phone/hardware_boot/tb.v']
    if cpu_wrapper:
        rtl[rtl.index('rtl/ngage_cpu.sv')] = container_path(cpu_wrapper)
    rtl += [container_path(arm9v2_netlist), *sorted(glob.glob('rtl/arm9v2/upstream/sim/stubs/*.sv')),
            'rtl/ngage_ddr_flash_adapter.v', 'rtl/ngage_ddr_flash_cache.v',
            'rtl/ngage_game_pcm.v', 'rtl/ngage_upp_dsp_pcm.v', container_path(out / 'tb.v')]
    real_sdram = []
    if sdram_model:
        rtl += ['rtl/ngage_sdram_adapter.v', 'rtl/ngage_sdram_clock.v', 'tests/phone/sdram/ddio_model.v',
                *sorted(glob.glob('rtl/sdram/jtframe_sdram64*.v')), container_path(sdram_model)]
        real_sdram = ['-DNGAGE_REAL_SDRAM', '-GSHORT_READS=1']
    if donor_sdram:
        rtl = [path for path in rtl if path != 'rtl/ngage_sdram_adapter.v' and
               not path.startswith('rtl/sdram/jtframe_sdram64')]
        rtl += ['rtl/ngage_sdram_stream.v',
                'rtl/sdram/ngage_sdram_scheduler.v' if stream_sdram else container_path(out / 'donor_sdram.sv')]
        real_sdram.append('-DNGAGE_FRAME_GAP_DONOR_SDRAM')
    if block_writeback:
        real_sdram.append('-DNGAGE_BLOCK_WRITEBACK')
    if handoff:
        rtl[rtl.index('rtl/ngage_sdram_adapter.v')] = container_path(out / 'ngage_sdram_adapter.v')
    if interleave:
        for path in ('rtl/ngage_sdram_adapter.v', 'rtl/sdram/jtframe_sdram64.v'):
            rtl[rtl.index(path)] = container_path(out / Path(path).name)
    if pin_waits:
        real_sdram.append('-DNGAGE_FRAME_GAP_PIN_WAIT')
    if posted_writes:
        real_sdram.append('-DNGAGE_FRAME_GAP_POSTED')
        rtl.append('tests/phone/sdram/frame_gap_posted.sv')
    obj = out / f'mmc{divider}-nos{hz}'
    with (out / f'build-{divider}-{hz}.log').open('w') as log:
        subprocess.run(DOCKER + ['verilator', IMAGE, '--binary', '--timing', '--assert', '-j', '2',
                       '-DNGAGE_RUNTIME_TRACE', '-DNGAGE_ARM9V2', '-DNGAGE_PRODUCTION_DDR',
                       '-DNGAGE_POWERUP_NORMAL', '-Wno-fatal', '-Wno-lint', '-Irtl/arm',
                       '--top-module', 'tb', '--Mdir', container_path(obj), '-GLINE_REFILL=1',
                       '-GSYS_CLK_HZ=78000000', '-GTIMER_CLK_DIV=3', '-GGAME_PCM=1',
                       f'-GFLASH_CACHE_BYTES={flash_cache_bytes}', '-GBOUNDED_CYCLES=120000000', *real_sdram,
                       f'-GNOS_TICK_HZ={hz}', f'-GMMC_CLK_DIV={divider}', *rtl],
                       cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    for cache in obj.glob('*.gch'):
        cache.unlink()
    return obj / 'Vtb'


def measure(out, exe, case, divider, hz, attempt, flash_cache_bytes):
    name = case['name']
    suffix = 'wrong' if attempt == 2 else str(attempt)
    log_path = out / f'{name}-{divider}-{hz}-{suffix}.log'
    trace = ['+sdram-trace=' + container_path(out / f'{name}-{divider}-{hz}-requests.txt')] if attempt == 0 else []
    with log_path.open('w') as log:
        completed = subprocess.run(DOCKER + [container_path(exe), IMAGE, '+ngage-compact-trace', '+no-board-log',
            '+core=' + container_path(out / f'{name}-{attempt == 2}.bin'),
            '+extension=' + container_path(FIRMWARE / 'extension.bin'),
            '+cdrive=' + container_path(out / 'cdrive.bin'),
            f'+begin_pc={case["begin"]:x}', f'+end_pc={case["end"]:x}',
            f'+payload_base={case["payload_base"]:x}', f'+helper_base={case["helper_base"]:x}', *trace],
            cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    if attempt == 2:
        assert completed.returncode != 0 and 'Guest output check rejected payload' in log_path.read_text(), log_path
        return None
    assert completed.returncode == 0, log_path
    passed, = find(log_path, 'PAYLOAD_PASS ')
    windows = find(log_path, 'PAYLOAD_RESULT ')
    assert len(windows) == 7 and passed['d2_lines'] == flash_cache_bytes // 32, log_path
    for rec, expected in zip(windows, case['windows']):
        assert rec['payload_ops'] == expected['payload_retire_proxy'], (log_path, rec, expected)
        assert rec['helper_ops'] == expected['helper_retire_proxy'], (log_path, rec, expected)
    return dict(windows=windows, memory_windows=find(log_path, 'V5_MEMORY_WINDOW '),
                total=passed, median_clocks=statistics.median(r['cycles'] for r in windows[2:]))


def delay_pin_service(bench, posted):
    # Retain real controller timing and add pressure in front of each backend.
    # The two extra DDR clocks apply once per returned burst, and the nine
    # SDRAM clocks apply once per scalar or 32-byte request.
    scalar = 'p_req' if posted else 'sreq'
    reset = 'p_reset' if posted else 'dma_reset || cold'
    visible_ready = 'p_line_ready' if posted else 'ram_line_ready'
    bench = swap(bench, f'.req({scalar}),.we(', '.req(profile_scalar_req),.we(')
    bench = swap(bench, f'.line_ready({visible_ready})', '.line_ready(profile_line_ready)')
    line_request = 'ram_line_req && !lock' + (' && p_idle' if posted else '')
    bench = swap(bench, f'.line_req({line_request})', '.line_req(profile_line_req && profile_line_allow)')
    bench = swap(bench, ' wire [1:0] ba_line;', f''' wire profile_line_req = {line_request};
 reg [3:0] profile_scalar_wait = 0, profile_line_wait = 0;
 wire profile_scalar_req = {scalar} && profile_scalar_wait == 9;
 wire profile_line_ready, profile_line_allow = profile_line_wait == 9;
 assign {visible_ready} = profile_line_ready && profile_line_allow;
 always @(posedge clk) begin
  if ({reset} || !{scalar}) profile_scalar_wait <= 0;
  else if (profile_scalar_wait != 9) profile_scalar_wait <= profile_scalar_wait + 1'b1;
  if (dma_reset || cold || !profile_line_req || (profile_line_ready && profile_line_allow))
   profile_line_wait <= 0;
  else if (!profile_line_allow) profile_line_wait <= profile_line_wait + 1'b1;
 end
 wire [1:0] ba_line;''')
    return swap(bench, 'ddelay<=3;ddr_remaining<=ddr_burst;', 'ddelay<=5;ddr_remaining<=ddr_burst;')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name', required=True)
    parser.add_argument('--case', action='append')
    parser.add_argument('--config', action='append', choices=('2:64', '1:64', '2:128', '1:128'))
    parser.add_argument('--arm9v2-netlist', type=Path, default=ROOT / 'rtl/arm9v2/arm925t_phone.v')
    parser.add_argument('--flash-cache-bytes', type=int, choices=(8192, 32768), default=8192)
    parser.add_argument('--sdram-model', type=Path, help='Verilator pin model prepared by run-real-sdram.sh')
    parser.add_argument('--cpu-wrapper', type=Path, help='alternate CPU wrapper for an isolated simulation trial')
    parser.add_argument('--posted-writes', action='store_true', help='test ordered scalar SDRAM posting')
    parser.add_argument('--interleave', action='store_true', help='test the donor bank map in the v5 controller')
    parser.add_argument('--pin-waits', action='store_true', help='add 2 DDR and 9 SDRAM request clocks')
    parser.add_argument('--handoff', choices=('completion', 'admit'), help='test a shorter v5 scalar SDRAM handoff')
    parser.add_argument('--donor-sdram', action='store_true', help='test the pinned ngage2 controller')
    parser.add_argument('--donor-wide', action='store_true', help='stream both BL8 reads in one donor request')
    parser.add_argument('--stream-sdram', action='store_true', help='test the v5 streaming controller sources')
    parser.add_argument('--block-writeback', action='store_true', help='send v5 dirty victims as two 16-byte writes in simulation')
    args = parser.parse_args()
    if args.donor_wide or args.stream_sdram:
        args.donor_sdram = True
    assert re.fullmatch(r'[a-zA-Z0-9_-]+', args.name)
    netlist = args.arm9v2_netlist.resolve()
    if not netlist.is_relative_to(ROOT) or not netlist.is_file():
        parser.error('--arm9v2-netlist must be a file in this checkout')
    if (args.posted_writes or args.interleave or args.pin_waits) and not args.sdram_model:
        parser.error('--posted-writes, --interleave and --pin-waits require the SDRAM pin model')
    if args.handoff and (not args.sdram_model or args.interleave):
        parser.error('--handoff uses the physical v5 controller with the stock bank map')
    if args.donor_sdram and (not args.sdram_model or args.handoff or args.pin_waits or
                            args.interleave or args.posted_writes):
        parser.error('--donor-sdram uses its own pin controller and write path')
    if args.block_writeback and not args.stream_sdram:
        parser.error('--block-writeback requires --stream-sdram')
    out = OUT / 'payload-clocks' / args.name
    out.mkdir(parents=True)
    if args.handoff:
        from frame_gap_handoff import generate
        generate(out, admit=args.handoff == 'admit')
    frozen_netlist = out / 'arm925t_phone.v'
    frozen_netlist.write_bytes(netlist.read_bytes())
    sdram_model = None
    if args.sdram_model:
        sdram_model = out / 'mt48lc16m16a2.v'
        sdram_model.write_bytes(args.sdram_model.read_bytes())
    cpu_wrapper = None
    if args.cpu_wrapper:
        cpu_wrapper = out / 'ngage_cpu.sv'
        cpu_wrapper.write_bytes(args.cpu_wrapper.read_bytes())
    configs = args.config or ('2:64', '2:128')
    profile = [tuple(map(int, pair.split(':'))) for pair in configs]
    all_cases = [case for case in qualified_inputs() if not args.case or case['name'] in args.case]
    assert all_cases and (not args.case or len(all_cases) == len(set(args.case)))
    original = (FIRMWARE / 'core.bin').read_bytes()
    assert digest(original) == ROM_SHA
    with (out / 'cdrive.bin').open('wb') as f:
        f.truncate(4194304)
    text = (ROOT / 'tests/phone/hardware_boot/tb.v').read_text()
    if args.donor_sdram:
        from frame_gap_donor_sdram import generate
        text = generate(out, text, wide=args.donor_wide, production=args.stream_sdram)
    if args.posted_writes:
        old_ports = '.phone_reset(dma_reset || cold),.init(mem_init),.req(sreq),.we(swe),.addr(sa),.din(sd),.be(sb),.ack(sack)'
        replacement = '.phone_reset(p_reset),.init(mem_init),.req(p_req),.we(p_we),.addr(p_addr),.din(p_data),.be(p_mask),.ack(p_ack)'
        assert text.count(old_ports) == 1
        text = text.replace(old_ports, replacement)
        line_port = '.line_req(ram_line_req && !lock),.line_addr(ram_line_addr),.line_ready(ram_line_ready)'
        assert text.count(line_port) == 1
        text = text.replace(line_port, '.line_req(ram_line_req && !lock && p_idle),.line_addr(ram_line_addr),.line_ready(p_line_ready)')
        text = text.replace(' wire [1:0] ba_line;', ''' wire p_reset,p_req,p_we,p_ack,p_idle,p_line_ready;
 wire [24:0] p_addr;
 wire [31:0] p_data;
 wire [3:0] p_mask;
 assign ram_line_ready = p_idle && p_line_ready;
 frame_gap_posted posted(.clk(clk),.cold_reset(cold),.client_reset(dma_reset || cold),.lock(lock),
  .req(sreq),.we(swe),.addr(sa),.data(sd),.mask(sb),.ack(sack),.line_idle(p_idle),
  .backend_reset(p_reset),.backend_req(p_req),.backend_we(p_we),.backend_addr(p_addr),
  .backend_data(p_data),.backend_mask(p_mask),.backend_ack(p_ack));
 wire [1:0] ba_line;''')
    if args.pin_waits:
        text = delay_pin_service(text, args.posted_writes)
    if args.interleave:
        from frame_gap_interleave import generate, overlay_phone
        generate(out)
        text = overlay_phone(text)
    assert text.count('if(cycles==BOUNDED_CYCLES)begin') == 1
    text = text.replace('if(cycles==BOUNDED_CYCLES)begin', 'if(cycles==BOUNDED_CYCLES) $fatal(1,"Payload timeout PC=%h", fetch_pc);\n   if(1\'b0) begin')
    observe = (HERE / 'payload_clock_observe.vh').read_text()
    (out / 'tb.v').write_text(text.rsplit('endmodule', 1)[0] + '\n' + observe + '\nendmodule\n')
    with ThreadPoolExecutor(max_workers=4) as pool:
        compiles = {(div, hz): pool.submit(compile_phone, out, div, hz, frozen_netlist,
                                           args.flash_cache_bytes, sdram_model, cpu_wrapper, args.posted_writes, args.interleave, args.pin_waits, args.handoff, args.donor_sdram, args.stream_sdram, args.block_writeback)
                    for div, hz in profile}
        rule = rules()
        for case in all_cases:
            for bad in (False, True):
                arrange_flash(out / f'{case["name"]}-{bad}.bin', case['bad' if bad else 'good'], case, original, rule)
        exes = {key: future.result() for key, future in compiles.items()}
        result = dict(status='RUNNING', configs=configs, netlist_sha256=digest(frozen_netlist.read_bytes()),
                      flash_cache_bytes=args.flash_cache_bytes, posted_writes=args.posted_writes, interleave=args.interleave, pin_waits=args.pin_waits, handoff=args.handoff, donor_sdram=args.donor_sdram, donor_wide=args.donor_wide, stream_sdram=args.stream_sdram,
                      sdram_model_sha256=digest(sdram_model.read_bytes()) if sdram_model else None, rows=[])
        if args.block_writeback:
            result['writeback_block_bytes'] = 16
            result['stream_adapter_sha256'] = digest((ROOT / 'rtl/ngage_sdram_stream.v').read_bytes())
        for case in all_cases:
            jobs = {key: [pool.submit(measure, out, exe, case, *key, attempt, args.flash_cache_bytes) for attempt in range(3)]
                    for key, exe in exes.items()}
            for (div, hz), futures in jobs.items():
                first, repeat, bad = [future.result() for future in futures]
                assert first == repeat and bad is None
                print(case['name'], f'MMC={78 // div} MHz NOS={hz} Hz', first['median_clocks'], flush=True)
                result['rows'].append(dict(case=case['name'], mmc_hz=78000000 // div, nos_hz=hz, **first))
            (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    result['status'] = 'PASS'
    (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
