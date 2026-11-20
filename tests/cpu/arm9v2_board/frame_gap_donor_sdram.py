"""Wire the pinned ngage2 SDRAM controller into the v5 simulation."""

from pathlib import Path
import subprocess

from frame_gap_early import swap

DONOR = Path('/Users/andreabogazzi/develop/ngage2')
REVISION = 'ff6dcff7f92a8ce999f2e89fdc08b873b5172404'

BRIDGE = ''' wire scrub_done, sdr_ready;
 wire sdr_req,sdr_we,sdr_line,sdr_busy,sdr_rvalid;
 wire [24:2] sdr_addr;
 wire [127:0] sdr_wdata;
 wire [15:0] sdr_wbe,sdr_dq;
 wire [31:0] sdr_rdata;
 wire [15:0] dq_write;
 tri [15:0] dq;
 wire [12:0] sdram_a;
 wire [1:0] bank;
 wire dqml,dqmh,nwe,ncas,nras,ncs,cke,memclk;
 ngage_sdram_clock forward_clock(.clk(clk),.sdram_clk(memclk));
 assign #5.5 sdr_dq = memory.Dq_reg;
 ngage_sdram_stream #(.WIDE_PORT(0), .SCRUB_BYTES(25'd32)) sadapter(
  .clk(clk),.cold(cold),.phone_reset(dma_reset || cold),.lock(mem_lock),.owner_ready(sdram_owner_ready),
  .req(sreq),.we(swe),.write_block(mem_write_block),.block_data(mem_block_data),
  .addr(sa),.din(sd),.be(sb),.ack(sack),.dout(sdata),
  .line_req(ram_line_req && !lock),.line_short(1'b0),.line_addr(ram_line_addr),.line_ready(ram_line_ready),
  .line_valid(ram_line_valid),.line_data(ram_line_data),.line_last(ram_line_last),
  .mem_req(sdr_req),.mem_we(sdr_we),.mem_line(sdr_line),.mem_addr(sdr_addr),
  .mem_wdata(sdr_wdata),.mem_wbe(sdr_wbe),.scrub_done(scrub_done),.mem_ready(sdr_ready),.mem_busy(sdr_busy),
  .mem_valid(sdr_rvalid),.mem_rdata(sdr_rdata));
 sdram #(.CLK_HZ(SYS_CLK_HZ)) ctrl(
  .clk(clk),.init(cold),.ready(sdr_ready),.req(sdr_req),.busy(sdr_busy),.we(sdr_we),
  .line(sdr_line),.addr(sdr_addr),.wdata(sdr_wdata),.wbe(sdr_wbe),.rvalid(sdr_rvalid),
  .rword(),.rdata(sdr_rdata),.sdram_cke(cke),.sdram_cs_n(ncs),.sdram_ras_n(nras),
  .sdram_cas_n(ncas),.sdram_we_n(nwe),.sdram_ba(bank),.sdram_a(sdram_a),
  .sdram_dqml(dqml),.sdram_dqmh(dqmh),.sdram_dq_o(dq_write),.sdram_dq_oe(),.sdram_dq_i(sdr_dq));
'''


def wide_read_port(controller):
    # This trial uses the donor's existing two halfword scalar writes.
    # Every line request from the v5 peer is a 32-byte aligned read.
    controller = swap(controller, 'END_RL = CAP + 8;', 'END_RL = CAP + 16;')
    controller = swap(controller, "(op_line ? (TW + 1)'(8) :",
                      "(op_line ? (TW + 1)'(16) :")
    controller = swap(controller, 'wire read_now =', """wire second_burst = state == ACCESS && !idle && !op_we && op_line && t == TW'(RCD + 8);
	wire read_now = second_burst ||""")
    return swap(controller, 'p_a[8:0] <= col_now;',
                "p_a[8:0] <= second_burst ? col_now + 9'd8 : col_now;")


def generate(out, bench, wide=False, production=False):
    ports = BRIDGE
    if production:
        ports = ports.replace("sdram #(", "ngage_sdram_scheduler #(").replace(
            ".line(sdr_line)", ".line(sdr_line),.read_short(1'b0)")
    else:
        controller = subprocess.check_output(['git', '-C', DONOR, 'show', f'{REVISION}:rtl/mem/sdram.sv'])
        if wide:
            controller = wide_read_port(controller.decode()).encode()
        (out / 'donor_sdram.sv').write_bytes(controller)
    if wide or production:
        ports = ports.replace('.WIDE_PORT(0)', '.WIDE_PORT(1)')
    bench = swap(bench, ' wire cpu_write_block, mem_write_block;',
                 ' wire cpu_write_block, mem_write_block, mem_lock;')
    bench = swap(bench, '.mem_req(sreq),.mem_we(swe),.mem_addr(sa)',
                 '.mem_req(sreq),.mem_we(swe),.mem_lock(mem_lock),.mem_addr(sa)')
    start = bench.index(' wire scrub_done,mem_init;')
    end = bench.index(' mt48lc16m16a2 memory(', start)
    return swap(bench, bench[start:end], ports)
