"""Profile E: commands separately on the existing actual-hps_io card fixture."""
import argparse
import json
from pathlib import Path
import re
import subprocess

from run import BASE, DOCKER, IMAGE, ROOT, change, original


def make_bench(source, restore_protocol):
    source = change(source, 'module actual_tb;', 'module actual_tb;\n  parameter SERIAL_HALF=1;')
    source = change(source, 'always #5 clk', 'always #6.410256 clk')
    start = source.index('  task mclk;')
    end = source.index('  task idle;', start)
    source = source[:start] + source[start:end].replace('repeat (3) tick;', 'repeat (SERIAL_HALF) tick;') + source[end:]
    source = change(source, 'repeat (13) @(negedge clk);', 'repeat (host_wait) @(negedge clk);')
    source = change(source, 'while (sample_dat && t < 1000)', 'while (sample_dat && t < 40000)')
    source = change(source, 'while (!present && j < 10000)', 'while (!present && j < 26000 + 3*host_wait)')
    if restore_protocol:
        source = change(source, 'assign h_count[0] = 0;\n  assign h_count[1] = 0;', '''assign h_count[0] = 7;
  assign h_count[1] = 7;
  integer restore_halfwords[2] = '{0, 0};
  reg [1:0] old_restore_ack = 0;
  always @(posedge clk) begin
    old_restore_ack <= h_ack[1:0];
    for (integer slot=0; slot<2; slot++)
      if (h_we && (h_ack[slot] || old_restore_ack[slot])) begin
        if (h_addr !== 13'(restore_halfwords[slot]) ||
            h_dout !== (16'hac00 | 16'(restore_halfwords[slot])))
          $fatal(1, "4 KiB HPS restore payload order/slot failed");
        restore_halfwords[slot]++;
      end
  end''')
        source = change(source, '      end else other_reads = other_reads + 1;', '''      end else begin
        if (hwrite || nwords != 2048 || current_lba != (part == 0 ? 32'h100 : 32'h200))
          $fatal(1,"4 KiB HPS restore command/slot framing failed");
        other_reads = other_reads + 1;
      end''')
        source = change(source, '    mount_mask = 1;\n    mount_hps', '''    if (restore_halfwords[0] != 2048 || restore_halfwords[1] != 2048)
      $fatal(1,"4 KiB HPS restore slot halfword count failed");
    $display("PASS 4 KiB HPS slot 0/1 command and all 4096 halfwords");
    mount_mask = 1;
    mount_hps''')
    source = change(source, '  integer base_reads, base_forwarded;', '''  integer base_reads, base_forwarded;
  integer host_wait = 13, phase_cycle, phase_reads, phase_writes, phase_bulk;
  initial void'($value$plusargs("host_wait=%d",host_wait));
  task start_phase;
    phase_cycle = clocks;
    phase_reads = card_reads;
    phase_writes = write_requests;
    phase_bulk = bulk_reads;
  endtask
  task end_phase(input string cmd);
    $display("MMC %s clocks=%0d host_reads=%0d host_writes=%0d bulk_reads=%0d",
             cmd, clocks-phase_cycle, card_reads-phase_reads, write_requests-phase_writes, bulk_reads-phase_bulk);
  endtask''')
    source = change(source, '''    r1(17, 0);
    read_data(0);
    idle(8);
    r1(18, 0);''', '''    start_phase();
    r1(17, 0);
    read_data(0);
    end_phase("cmd17");
    idle(8);
    start_phase();
    r1(18, 0);''')
    source = change(source, '''    for (j = 0; j < 8; j = j + 1) read_data(j * 512);
    r1(12, 0);''', '''    for (j = 0; j < 8; j = j + 1) read_data(j * 512);
    r1(12, 0);
    end_phase("cmd18_8");''')
    source = change(source, '    r1(24, 512);', '    start_phase();\n    r1(24, 512);')
    source = change(source, "    write_block(8'h67);", "    write_block(8'h67);\n    end_phase(\"cmd24\");")
    comment = '    // Both multiwrite blocks persist without changing the metadata footer.\n'
    source = change(source, comment + '    r1(25, 0);', comment + '    start_phase();\n    r1(25, 0);')
    return change(source, '''    if (token != 2 || writes != baseline + 2) fail("CMD25 second block persistence");
    r1(12, 0);''', '''    if (token != 2 || writes != baseline + 2) fail("CMD25 second block persistence");
    r1(12, 0);
    end_phase("cmd25_2");''')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name', required=True)
    parser.add_argument('--half', type=int, default=1)
    parser.add_argument('--restore-protocol', action='store_true')
    args = parser.parse_args()
    if not re.fullmatch(r'[\w.-]+', args.name):
        parser.error('invalid run name')
    out = Path('build/sim/disk-access') / args.name
    out.mkdir(parents=True)
    hps = out/'hps_io.sv'
    hps.write_text(original('sys/hps_io.sv'))
    prep = original('tests/phone/raw_save/prepare_hps.py').replace("Path('sys/hps_io.sv')", f"Path('{hps}')")
    prep = prep.replace("Path('build/sim/unit-raw-save-hps/hps-compat.sv')", f"Path('{out}/hps-compat.sv')")
    subprocess.run(['python3', '-c', prep], check=True)
    paths = []
    for name in ('ngage_mmc_hps.v', 'ngage_mmc_card.v', 'ngage_mmc_dpram.v'):
        path = out/name
        path.write_text(original('rtl/'+name))
        paths.append(str(path))
    bench = out/'actual_tb.sv'
    bench.write_text(make_bench(original('tests/phone/mmc_hps/actual_tb.sv'), args.restore_protocol))
    with (out/'build.log').open('w') as log:
        subprocess.run(DOCKER + ['verilator', IMAGE, '--binary', '--timing', '--assert', '-j', '2',
                       '-Wno-fatal', '-Wno-lint', '--top-module', 'actual_tb',
                       f'-GSERIAL_HALF={args.half}', '--Mdir', str(out/'obj'),
                       str(out/'hps-compat.sv'), *paths, str(bench)], cwd=ROOT, stdout=log,
                       stderr=subprocess.STDOUT, check=True)
    rows = []
    for wait in (13, 256, 4096):
        path = out/f'run-{wait}.log'
        with path.open('w') as log:
            subprocess.run(DOCKER + ['/work/'+str(out/'obj/Vactual_tb'), IMAGE, f'+host_wait={wait}'],
                           cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
        raw = path.read_text()
        assert 'PASS actual three-slot MMC HPS' in raw, path
        if args.restore_protocol:
            assert 'PASS 4 KiB HPS slot 0/1' in raw, path
        metrics = {}
        for rec in re.findall(r'^MMC (.*)$',raw,re.M):
            key, data = rec.split(' ',1)
            metrics[key] = {k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',data)}
        assert len(metrics) == 4, path
        rows.append(dict(wait=wait, intervals=metrics))
    (out/'result.json').write_text(json.dumps(dict(status='PASS', baseline=BASE, system_hz=78000000,
                                                 serial_half=args.half,rows=rows), indent=2)+'\n')
    print(f'PASS {out}')


if __name__ == '__main__':
    main()
