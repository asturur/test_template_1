`timescale 1ns / 1ps
module background_load_lock_tb #(
    parameter OWNED = 0
);
  reg clk = 0, reset = 1;
  reg read = 0, hit = 0, fault = 0, cacheable = 1;
  // Supply the two D-cache views exactly as a checked lookup register
  // does. The original path sees Q, the new authorization sees its D.
  reg  [2:0] checked;
  wire [2:0] checked_next = reset ? 3'b100 : {cacheable, fault, hit};
  always @(posedge clk) checked <= checked_next;
  wire permit = checked[2] && !checked[1];
  wire permit_next = checked_next[2] && !checked_next[1];
  wire fast;
  reg wb_ack = 0, wb_error = 0;
  reg [31:0] address = 0, next_address = 0, wb_data = 0;
  reg [5:0] destination = 0;
  wire idle, fill, ack, error, lock_valid, wb_stb;
  wire [ 5:0] lock_tag;
  wire [31:0] returned_data;
  wire [63:0] bitmap, returned;
  integer tag, hits = 0, fills = 0, returns = 0;

  ngage2_zap_dcache_fsm #(
      .CACHE_SIZE(16384),
      .CACHE_LINE(32),
      .WAYS(2),
      .FLAT_ACK(1),
      .LOCK_SPLIT(1),
      .OWNED_FAST_ACK(OWNED)
  ) cache (
      .i_clk(clk),
      .i_reset(reset),
      .i_address(address),
      .i_address_check(next_address),
      .i_cache_hit_early(checked[0]),
      .i_cache_hit_early_next(checked_next[0]),
      .i_hit_ok(permit),
      .i_hit_ok_next(permit_next),
      .i_rd(read),
      .i_wr(1'b0),
      .i_din(32'b0),
      .i_ben(4'hf),
      .i_align_fault(1'b0),
      .i_va(address),
      .i_ldfmt(6'b0),
      .i_reg_idx(64'd1 << destination),
      .i_reg_idx_bin(destination),
      .o_lock(bitmap),
      .i_lock_owner_hold(destination),
      .i_lock_owner_advance(destination),
      .i_lock_owner_move(1'b0),
      .o_lock_any(lock_valid),
      .o_lock_tag(lock_tag),
      .o_reg_dat(returned_data),
      .o_reg_idx(returned),
      .o_ack(ack),
      .o_err(error),
      .i_cache_en(1'b1),
      .i_writebuffer_en(1'b0),
      .i_bufferable(1'b0),
      .i_swp(1'b0),
      .i_post_full(1'b0),
      .i_post_full_next(1'b0),
      .i_cache_inv(1'b0),
      .i_cache_clean(1'b0),
      .i_line_req(1'b0),
      .i_line_done_tr(1'b0),
      .i_cache_line(256'b0),
      .i_cache_word(32'h55667788),
      .i_cache_tag_dirty(1'b0),
      .i_cache_tag(46'b0),
      .i_cache_tag_valid(1'b0),
      .i_cache_hit(checked[0]),
      .i_cache_victim_halves(2'b0),
      .i_cache_hit_halves(2'b0),
      .i_cache_hit_dirty(1'b0),
      .i_cache_way(1'b0),
      .i_cache_clean_done(1'b0),
      .i_cache_inv_done(1'b0),
      .i_phy_addr(address),
      .i_fsr(8'h0f),
      .i_far(address),
      .i_fault(checked[1]),
      .i_cacheable(checked[2]),
      .i_wt(1'b0),
      .i_busy(1'b0),
      .i_tlb_hit_ready(permit),
      .i_tlb_ready_next(permit_next),
      .o_ack_fast(fast),
      .o_idle(idle),
      .o_fill_busy(fill),
      .o_wb_stb_ff(wb_stb),
      .i_wb_ack(wb_ack),
      .i_wb_dat(wb_data),
      .i_wb_err(wb_error),
      .i_block_enable(1'b0)
  );

  always #5 clk = !clk;
  always @(posedge clk)
    if (!reset && bitmap !== (lock_valid ? 64'd1 << lock_tag : 64'b0))
      $fatal(1, "Visible lock token and bitmap diverged");

  task tick;
    begin
      @(negedge clk);
      #1;
    end
  endtask

  task start_miss;
    input [5:0] tag;
    input [31:0] base;
    input [2:0] critical;
    begin
      while (!idle) tick;
      address = base + 4 * critical;
      next_address = base + 32'h1000;
      destination = tag;
      hit = 0;
      tick;
      read = 1;
      #1;
      if (!ack || !fast || error) $fatal(1, "Read miss was not accepted");
      tick;
      if (!fill || !lock_valid || lock_tag !== tag || bitmap !== (64'd1 << tag))
        $fatal(1, "Wrong miss owner %0d", tag);
      read = 0;
    end
  endtask

  task drain_fill;
    input [5:0] tag;
    input [2:0] critical;
    integer beat;
    begin
      for (beat = 0; beat < 8; beat = beat + 1) begin
        while (!wb_stb) tick;
        wb_data = 32'h12340000 + beat;
        wb_ack  = 1;
        tick;
        if (beat == critical) begin
          if (returned !== (64'd1 << tag) || returned_data !== wb_data || !lock_valid)
            $fatal(1, "Critical word lost the original owner %0d", tag);
          returns = returns + 1;
        end else if (returned !== 0) $fatal(1, "Premature or repeated return");
        wb_ack = 0;
        tick;
        if (lock_valid !== (beat < critical)) $fatal(1, "Wrong lock release edge");
      end
      while (!idle) tick;
      fills = fills + 1;
    end
  endtask

  initial begin
    repeat (2) tick;
    reset = 0;
    for (tag = 0; tag < 64; tag = tag + 1) begin
      start_miss(tag[5:0], 32'h0a010000 + 32 * tag, tag[2:0]);
      // A hit to the prechecked disjoint line must leave the older
      // miss's return owner intact, even with a different destination.
      address = next_address;
      destination = tag[5:0] ^ 6'h3f;
      hit = 1;
      tick;
      read = 1;
      #1;
      if (!ack || !fast || !fill || !lock_valid || lock_tag !== tag[5:0])
        $fatal(1, "Hit under miss did not preserve the fill owner");
      tick;
      hits = hits + 1;
      read = 0;
      hit  = 0;
      drain_fill(tag[5:0], tag[2:0]);
    end

    fault = 1;
    tick;
    read = 1;
    destination = 0;
    #1;
    if (!ack || !error || fast) $fatal(1, "Fault did not terminate the read");
    tick;
    if (lock_valid || returned) $fatal(1, "Fault installed a background lock");
    read = 0;
    fault = 0;

    cacheable = 0;
    tick;
    read = 1;
    while (!wb_stb) tick;
    wb_error = 1;
    tick;
    if (!ack || !error || !fast || lock_valid || returned)
      $fatal(1, "Uncached abort leaked a lock");
    read = 0;
    wb_error = 0;
    cacheable = 1;
    tick;

    start_miss(6'd0, 32'h0a040000, 3'd7);
    reset = 1;
    tick;
    reset  = 0;
    wb_ack = 1;
    tick;
    if (lock_valid || bitmap || returned) $fatal(1, "Reset retained a canceled fill owner");
    wb_ack = 0;
    start_miss(6'd39, 32'h0a050000, 3'd0);
    drain_fill(6'd39, 3'd0);
    $display("PASS background load tags fills=%0d returns=%0d hits_under_miss=%0d aborts=2 reset=1",
             fills, returns, hits);
    $finish;
  end

  initial begin
    #1000000;
    $fatal(1, "Background load lock watchdog expired");
  end
endmodule
