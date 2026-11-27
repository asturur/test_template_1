"""Measure the v5 NOR and persistence path with a disposable file-operation proxy."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
BASE = 'dfe4bc1a17c58ef2b652a4b650f129e1541800d4'
IMAGE = 'jotego/simulator:arm64'
DOCKER = ['docker', 'run', '--rm', '--pull=never', '--network', 'none',
          '--platform', 'linux/arm64', '-v', f'{ROOT}:/work', '-w', '/work', '--entrypoint']


def original(path):
    return subprocess.check_output(['git', 'show', f'{BASE}:{path}'], cwd=ROOT, text=True)


def change(source, old, new):
    if source.count(old) != 1:
        raise ValueError(f'unexpected baseline near {old!r}')
    return source.replace(old, new)


def update_on_hit(source):
    source = change(source, '    wire invalidate = state == LOOKUP && writing && cacheable && tag_hit && |mask;',
                    '''    wire invalidate = 1'b0;
    reg resident_write;
    always @(posedge clk)
        if (reset) resident_write <= 0;
        else if (state == LOOKUP) resident_write <= writing && cacheable && tag_hit && |mask;
    wire committed_update = state == WAIT_MEM && mem_done && writing && resident_write && !reset;
    wire [7:0] update_bytes = address[2] ? {mask, 4'b0} : {4'b0, mask};''')
    source = change(source, '.AW(INDEX_BITS + 2),\n        .DW(64)', '.AW(INDEX_BITS + 2),\n        .DW(64),\n        .BYTE_WIDTH(8)')
    for old, new in (
        ('.addr_a({index, beat[1:0]})', '.addr_a({index, committed_update ? address[4:3] : beat[1:0]})'),
        ('.data_a(mem_beat_data)', '.data_a(committed_update ? {write_data, write_data} : mem_beat_data)'),
        ('.we_a  (fill_beat && !reset)', '.we_a  (committed_update ? update_bytes : {8{fill_beat && !reset}})'),
        (".data_b(64'b0),\n        .we_b  (1'b0)", ".data_b(64'b0),\n        .we_b  (8'b0)"),
    ):
        source = change(source, old, new)
    return source


def production_cache(_):
    return (ROOT / 'rtl/ngage_ddr_flash_cache.v').read_text()


def nor_bench(source, proxy):
    if not proxy:
        return source
    source = change(source, '  reg clk = 0;\n  always #5 clk = ~clk;', '''  reg clk = 0;
  always #6.410256 clk = ~clk;''')
    source = change(source, '  reg [15:0] disk[0:1279], header[0:255], original_disk[0:1279];',
                    '  reg [15:0] disk[0:8959], header[0:255], original_disk[0:8959];')
    source = change(source, '.C_SECTORS(2)', '.C_SECTORS(32)')
    source = change(source, ".SD_TIMEOUT(100000),", '''.SD_TIMEOUT(100000),
      .AUTO_QUIET_CYCLES(1024),
      .AUTO_MAX_AGE_CYCLES(8192),''')
    source = change(source, ".autosave_enable(1'b0)", '.autosave_enable(proxy_auto)')
    source = change(source, "psector - 14'd8190", "psector - 14'd8160")
    source = change(source, '      repeat (8) begin', '      repeat (host_wait) begin')
    source = change(source, 'while (!frsp && t < 5000)', 'while (!frsp && t < 400000)')
    source = change(source, 'if ((current_lba > 1))', 'if (current_lba >= (part == 0 ? 32 : 2))')
    source = change(source, '(part == 1 ? 2 : 0)', '(part == 1 ? 32 : 0)')
    source = change(source, '      if (part < 2) current_lba =', '''      if (status_word[1])
        $display("BACKING_WRITE slot=%0d lba=%0d active=%0d", part, current_lba, guest_active);
      if (part < 2) current_lba =''')
    source = change(source, '  initial begin : host', '''  integer host_wait = 8;
  bit proxy_auto = 0;
  initial begin : host''')
    source = change(source, '  ngage_cflash flash (\n      clk,\n      reset,\n      1\'b0,', '''  bit warm_flash_reset = 0, cold_flash_reset = 0;
  ngage_cflash flash (
      clk,
      reset || warm_flash_reset,
      cold_flash_reset,''')
    source = change(source, '      end else $fatal(1, "unexpected DDR read %h", address);', '''      end else if (address == (32'h31410000 >> 3)) begin
        read_ddr = 64'hfca53132_1a55ffe0;
      end else if (address > (32'h31410000 >> 3) && address < (32'h31410020 >> 3)) begin
        read_ddr = 64'b0;
      end else $fatal(1, "unexpected DDR read %h", address);''')
    lo = source.index('  initial begin : test')
    hi = source.index('  initial begin\n    #10000000;', lo)
    source = source[:lo] + (HERE / 'nor_proxy.vh').read_text() + '\n' + source[hi:]
    return change(source, '#10000000;', '#100000000;')


def prepare(out):
    sources = {}
    disk = original('sys/hps_io.sv')
    prep = original('tests/phone/raw_save/prepare_hps.py')
    helper = out / 'prepare_hps.py'
    helper.write_text(prep.replace("Path('sys/hps_io.sv')", f"Path('{out}/hps_io.sv')").replace(
        "Path('build/sim/unit-raw-save-hps/hps-compat.sv')", f"Path('{out}/hps-compat.sv')"))
    (out / 'hps_io.sv').write_text(disk)
    subprocess.run(['python3', str(helper)], cwd=ROOT, check=True)
    line = next(l for l in original('tests/phone/raw_save/run-nor.sh').splitlines() if l.startswith('verilator '))
    for path in re.findall(r'(?:rtl/[^ ]+\.(?:sv|v)|tests/phone/raw_save/nor_tb\.sv)', line):
        f = out / Path(path).name
        f.write_text(original(path))
        sources[path] = f
    return sources


def simulate(out, prepared, policy, proxy, waits, autosave, erase_line):
    leg = out / f'{policy}-{"proxy" if proxy else "regression"}'
    leg.mkdir()
    sources = dict(prepared)
    cache_changes = {'scalar': lambda source: source, 'update': update_on_hit, 'production': production_cache}
    edits = [
        ('rtl/ngage_ddr_flash_cache.v', cache_changes[policy]),
        ('tests/phone/raw_save/nor_tb.sv', lambda s: nor_bench(s, proxy)),
    ]
    if erase_line:
        from erase_line import connect_erase_line, nor_erase_line
        edits += [('rtl/ngage_cflash.sv', nor_erase_line),
                  ('tests/phone/raw_save/nor_tb.sv', connect_erase_line)]
    for src, operation in edits:
        target = leg / sources[src].name
        target.write_text(operation(sources[src].read_text()))
        sources[src] = target
    with (leg / 'build.log').open('w') as log:
        subprocess.run(DOCKER + ['verilator', IMAGE, '--binary', '--timing', '--assert', '-j', '2',
                       '-Wno-fatal', '-Wno-lint', '--top-module', 'tb', '-GBULK=1', '-GSTREAM_TRANSPORT=1',
                       '-GFLASH_CACHE_BYTES=32768', '--Mdir', str(leg/'obj'), str(out/'hps-compat.sv'),
                       *map(str, sources.values())], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    rows = []
    for wait in waits if proxy else [None]:
        for auto in [False, True] if proxy and autosave else [False]:
            path = leg / f'run-{wait}-{int(auto)}.log'
            args = [] if wait is None else [f'+host_wait={wait}'] + (['+proxy_auto'] if auto else [])
            with path.open('w') as log:
                subprocess.run(DOCKER + ['/work/'+str(leg/'obj/Vtb'), IMAGE, *args], cwd=ROOT,
                               stdout=log, stderr=subprocess.STDOUT, check=True)
            raw = path.read_text()
            if proxy:
                assert 'PASS disk proxy' in raw, path
                measures = {}
                for record in re.findall(r'^DISK (.*)$', raw, re.M):
                    name, values = record.split(' ', 1)
                    measures[name] = {key: int(value) for key, value in re.findall(r'(\w+)=(\d+)', values)}
                rows.append(dict(policy=policy, erase_line=erase_line, wait=wait, autosave=auto, intervals=measures))
            else:
                assert 'PASS raw NOR' in raw and 'PASS D2 raw NOR' in raw, path
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name', required=True)
    parser.add_argument('--policy', choices=('scalar', 'update', 'production'), action='append')
    parser.add_argument('--wait', type=int, action='append')
    parser.add_argument('--regression', action='store_true')
    parser.add_argument('--autosave', action='store_true')
    parser.add_argument('--erase-line', action='store_true')
    args = parser.parse_args()
    if not re.fullmatch(r'[\w.-]+', args.name):
        parser.error('invalid run name')
    out = Path('build/sim/disk-access') / args.name
    out.mkdir(parents=True)
    prepared = prepare(out)
    rows = []
    for policy in args.policy or ('scalar', 'update'):
        rows += simulate(out, prepared, policy, not args.regression, args.wait or [8, 256, 4096],
                         args.autosave, args.erase_line)
    evidence = dict(status='PASS', baseline=BASE, system_hz=78000000, rows=rows,
                    proxy_test_sha256=hashlib.sha256((HERE / 'nor_proxy.vh').read_bytes()).hexdigest(),
                    source_sha256={name: hashlib.sha256(path.read_bytes()).hexdigest()
                                   for name, path in prepared.items()})
    (out/'result.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(f'PASS {out}')


if __name__ == '__main__':
    main()
