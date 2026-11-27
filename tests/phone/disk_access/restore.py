"""Measure the existing C:/PMM restore engine behind a 512-byte or 4 KiB HPS peer."""
import argparse
import json
import re
import subprocess
from pathlib import Path

from run import BASE, DOCKER, HERE, IMAGE, ROOT, change, original


def make_bench(source):
    source = change(source, 'parameter BULK=0;', 'parameter BULK=1, HPS_BATCH=0;')
    source = change(source, '#5 clk', '#6.410256 clk')
    source = change(source, '.SD_TIMEOUT(5000)', '.SD_TIMEOUT(100000)')
    start = source.index('assign ack=hs==1')
    end = source.index('function automatic integer ram_index', start)
    source = source[:start] + source[end:]
    start = source.index('always @(posedge clk) begin\n case(hs)')
    end = source.index('task tick;', start)
    source = source[:start] + (HERE / 'restore_host.vh').read_text() + '\n' + source[end:]
    source = change(source, 'wait(mounted||error);if(error)$fatal(1,"mount failed state=%d",dut.state);', '''
 wait(mounted||error);
 if (short_packet || replace_image) begin
  if (!error || mounted || writes) $fatal(1, "invalid host data partially restored");
  $display("PASS restore fault left DDR untouched");
  $finish;
 end
 if(error)$fatal(1,"mount failed state=%d",dut.state);''')
    source = change(source, 'task mount_save;begin', 'task mount_save;begin\n mount_start=cycle;\n mount_write_start=writes;')
    source = change(source, 'repeat(8330)tick();mount_save();', 'repeat(8330)tick();mount_save();\n report_restore("mount");')
    source = change(source, '\n mount_save();\n for', '\n mount_save();\n report_restore("remount");\n for')
    source = change(source, '#2000000000;', '#4000000000;')
    return source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name', required=True)
    parser.add_argument('--batch', choices=(0, 1), type=int, action='append')
    parser.add_argument('--wait', type=int, action='append')
    args = parser.parse_args()
    if not re.fullmatch(r'[\w.-]+', args.name):
        parser.error('invalid run name')
    out = Path('build/sim/disk-access') / args.name
    out.mkdir(parents=True)
    line = next(l for l in original('tests/phone/raw_save/run-full.sh').splitlines() if l.startswith('verilator '))
    sources = []
    for path in re.findall(r'rtl/[^ ]+\.(?:sv|v)', line):
        target = out / Path(path).name
        target.write_text(original(path))
        sources.append(str(target))
    bench = out/'full_tb.sv'
    bench.write_text(make_bench(original('tests/phone/raw_save/full_tb.sv')))
    rows = []
    for batch in args.batch or [0, 1]:
        obj = out/f'obj-{batch}'
        with (out/f'build-{batch}.log').open('w') as log:
            subprocess.run(DOCKER + ['verilator', IMAGE, '--binary', '--timing', '--assert', '-j', '2',
                           '-Wno-fatal', '-Wno-lint', '--top-module', 'tb', f'-GHPS_BATCH={batch}',
                           '--Mdir', str(obj), *sources, str(bench)], cwd=ROOT, stdout=log,
                           stderr=subprocess.STDOUT, check=True)
        configs = [(f'{w}', [f'+host_wait={w}']) for w in args.wait or [8, 256, 4096]]
        configs += [('short', ['+short'])] + ([('replace', ['+replace'])] if batch else [])
        for key, plusargs in configs:
            path = out/f'{batch}-{key}.log'
            with path.open('w') as log:
                subprocess.run(DOCKER + ['/work/'+str(obj/'Vtb'), IMAGE, *plusargs], cwd=ROOT,
                               stdout=log, stderr=subprocess.STDOUT, check=True)
            raw = path.read_text()
            if key in ('short', 'replace'):
                assert 'PASS restore fault left DDR untouched' in raw, path
                continue
            assert 'PASS raw full-size' in raw, path
            metrics = {}
            for match in re.findall(r'^RESTORE (.*)$', raw, re.M):
                phase, values = match.split(' ', 1)
                metrics[phase] = {k: int(v) for k, v in re.findall(r'(\w+)=(\d+)', values)}
            assert set(metrics) == {'mount', 'remount'}, path
            rows.append(dict(batch=batch, wait=int(key), intervals=metrics))
    (out/'result.json').write_text(json.dumps(dict(status='PASS', baseline=BASE, system_hz=78000000, rows=rows),
                                            indent=2)+'\n')
    print(f'PASS {out}')


if __name__ == '__main__':
    main()
