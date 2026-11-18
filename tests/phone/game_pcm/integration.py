"""Exercise the game PCM MMIO and attached MMC together on the production ARM."""
import argparse
from pathlib import Path
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = ROOT / 'tests/phone/mmc_mister'
HERE = Path(__file__).resolve().parent
IMAGE = 'jotego/simulator:arm64'


def replace(text, before, after):
    assert text.count(before) == 1, before
    return text.replace(before, after)


def run(out):
    out.mkdir(parents=True, exist_ok=False)
    sim_path = str(out.relative_to(ROOT))
    arm = (FIXTURE / 'program.S').read_text()
    arm = replace(arm, 'start:\n', 'start:\n' + (HERE / 'start.S').read_text())
    mark = ' ldr r0,=0x0a000100\n put r0,0,0x50415353'
    arm = replace(arm, mark, (HERE / 'finish.S').read_text() + mark)
    asm = out / 'program.S'
    obj = out / 'program.o'
    elf = out / 'program.elf'
    asm.write_text(arm)
    subprocess.run(['arm-none-eabi-gcc', '-c', '-mcpu=arm920t', '-marm', asm, '-o', obj], check=True)
    subprocess.run(['arm-none-eabi-ld', '-T', ROOT / 'sim/programs/link.ld', obj, '-o', elf], check=True)
    subprocess.run(['arm-none-eabi-objcopy', '-O', 'binary', elf, out / 'program.bin'], check=True)
    prepare = FIXTURE / 'prepare.py'
    src = replace(prepare.read_text(), "root / 'build/sim/unit-mmc-mister'", f'Path({str(out)!r})')
    subprocess.run([sys.executable, '-B', '-c', src.replace(
        'Path(__file__).resolve().parents[3]', f'Path({str(ROOT)!r})')], check=True)

    tb = (FIXTURE / 'tb.v').read_text().replace('build/sim/unit-mmc-mister', sim_path)
    # The inherited guest deliberately attempts a write and expects MMC WP.
    tb = replace(tb, ".hps_img_readonly(1'b0)", ".hps_img_readonly(1'b1)")
    tb = replace(tb, ' wire [24:0] fast_addr,merge_addr;', '''
 wire [24:0] fast_addr,merge_addr;
 wire pcm_req, pcm_ack;
 wire [24:0] pcm_addr;
 wire [31:0] pcm_data;
 wire [15:0] pcm_l, pcm_r;
 integer played=0, reads_during_mmc=0;
 reg signed_channels=0, done_irq=0;
 always @(posedge clk) begin
  if (pcm_ack) played <= played + 1;
  if (pcm_ack && mmc_active) reads_during_mmc <= reads_during_mmc + 1;
  if (pcm_l == 16'hf000 && pcm_r == 16'h0800) signed_channels <= 1;
  if (dut.pcm_irq) done_irq <= 1;
 end
''')
    tb = replace(tb, '.DMA_LOCAL(1))', '.DMA_LOCAL(1),.GAME_PCM(1),.SYS_CLK_HZ(78000000))')
    tb = replace(tb, '  .dma_sdram_req(fast_req)', '''
  .pcm_sdram_req(pcm_req),.pcm_sdram_addr(pcm_addr),.pcm_sdram_ack(pcm_ack),
  .pcm_sdram_data(pcm_data),.pcm_left(pcm_l),.pcm_right(pcm_r),
  .dma_sdram_req(fast_req)''')
    tb = replace(tb, ' .lcd_req(fast_req)', '''
 .pcm_req(pcm_req),.pcm_addr(pcm_addr),.pcm_ack(pcm_ack),.pcm_rdata(pcm_data),
 .lcd_req(fast_req)''')
    tb = replace(tb, "      if(saved_sa==25'h100)begin", """
      if(saved_sa==25'h100)begin
       if (played != 64 || !reads_during_mmc || !signed_channels || !done_irq)
        $fatal(1,"PCM reads=%0d MMC overlap=%0d signed=%0d irq=%0d",played,reads_during_mmc,signed_channels,done_irq);
       $display("PASS signed game PCM: %0d reads, %0d during MMC, DONE IRQ observed",played,reads_during_mmc);
""")
    (out / 'tb.v').write_text(tb)
    raw = (FIXTURE / 'run.sh').read_text().split("-c '", 1)[1].split(' > build/sim/unit-mmc-mister/build.log', 1)[0]
    sources = [o for o in shlex.split(raw) if o.endswith(('.v', '.sv'))]
    sources.remove('tests/phone/mmc_mister/tb.v')
    sources.extend(('rtl/ngage_game_pcm.v', 'rtl/ngage_upp_dsp_pcm.v', f'{sim_path}/tb.v'))
    source_args = ' '.join(shlex.quote(x) if '*' not in x else x for x in sources)
    step = ('verilator --binary --timing --assert -j 3 -Wno-fatal -Wno-lint '
            f'-Irtl/arm --top-module tb --Mdir {sim_path}/obj '
            f'{source_args} > {sim_path}/build.log 2>&1 && '
            f'{sim_path}/obj/Vtb > {sim_path}/run.log 2>&1')
    subprocess.run(['docker','run','--rm','--pull','never','--network','none','--platform',
                    'linux/arm64','-v',f'{ROOT}:/work','-w','/work','--entrypoint','/bin/sh',
                    IMAGE,'-ec',step], check=True)
    output = (out / 'run.log').read_text()
    assert 'PASS signed game PCM:' in output and 'PASS authored ARM production MMC' in output
    print('\n'.join(line for line in output.splitlines() if line.startswith('PASS ')))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('name')
    args = parser.parse_args()
    assert args.name and all(c in 'abcdefghijklmnopqrstuvwxyz0123456789-' for c in args.name)
    run(ROOT / 'build/sim' / args.name)
