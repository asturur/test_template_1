`timescale 1ns/1ps
module test;
    reg clk=0, reset=1, dav=0;
    reg [31:0] instruction=0, write_data=0;
    wire done, reg_en, l4, rr, dc_inv,ic_inv,dc_clean,ic_clean,dt_inv,it_inv;
    wire [31:0] reg_data;
    wire [5:0] dc_base;
    wire dc_lock,drain,prefetch;reg dc_lock_done=1,buffer_empty=1,irq=0,fiq=0,prefetch_done=1;
    wire [5:0] wr_index,rd_index;
    reg [31:0] captured=0;
    integer cycles=0;
    reg touched_cache=0;
    always #5 clk=~clk;
    zap_cp15_cb #(.CP15_L4_DEFAULT(1'b1),.CODE_CACHE_SIZE(16384),.DATA_CACHE_SIZE(16384),
                  .CODE_CACHE_LINE(32),.DATA_CACHE_LINE(32)) dut (
      .i_clk(clk),.i_reset(reset),.i_cp_word(instruction),.i_cp_dav(dav),.o_cp_done(done),
      .i_cpsr(32'h000000d3),.o_reg_en(reg_en),.o_reg_wr_data(reg_data),
      .i_reg_rd_data(write_data),.o_reg_wr_index(wr_index),.o_reg_rd_index(rd_index),
      .i_fsr(8'b0),.i_far(32'b0),.o_l4_enable(l4),.o_cache_rr(rr),.o_dcache_lock_base(dc_base),.o_dcache_lock_write(dc_lock),
      .o_dcache_inv(dc_inv),.o_icache_inv(ic_inv),.o_dcache_clean(dc_clean),
      .o_icache_clean(ic_clean),.o_dtlb_inv(dt_inv),.o_itlb_inv(it_inv),
      .i_icache_prefetch_done(prefetch_done),.o_icache_prefetch(prefetch),.i_write_buffer_empty(buffer_empty),.i_irq(irq),.i_fiq(fiq),.o_drain_write_buffer(drain),.i_dcache_lock_done(dc_lock_done),.i_icache_lock_done(1'b1),.i_dcache_inv_done(1'b1),.i_icache_inv_done(1'b1),
      .i_dcache_clean_done(1'b1),.i_icache_clean_done(1'b1)
    );
    always @(posedge clk) begin
        cycles<=cycles+1;
        if(reg_en && wr_index!=16) captured<=reg_data;
        if (dc_inv || ic_inv || dc_clean || ic_clean) touched_cache<=1;
        if(cycles>500) $fatal(1,"CP15 test timeout");
    end
    task automatic issue(input [31:0] op,input [31:0] data);
      begin
        @(negedge clk);instruction=op;write_data=data;dav=1;
        while(!done) @(negedge clk);
        dav=0;repeat(3) @(negedge clk);
      end
    endtask
    task automatic read_control;
      begin issue(32'hee110f10,0); end
    endtask
    initial begin
      repeat(4) @(negedge clk);reset=0;repeat(3) @(negedge clk);
      issue(32'hee100f10,0); // MRC p15,0,r0,c0,c0,0: processor ID
      if ((captured & 32'hfffffff0) !== 32'h41129200)
        $fatal(1,"ARM920 implementer/architecture/part ID incorrect: %h",captured);
      issue(32'hee100f30,0);
      if (captured !== 32'h0d172172) $fatal(1,"cache type register: %h",captured);
      read_control();
      if ((captured & 32'h00004c00) !== 0) $fatal(1,"ARM920 reset RR/reserved bits incorrect: %h",captured);
      if ((captured & 32'h78) !== 32'h78) $fatal(1,"fixed control bits incorrect: %h",captured);
      if (!l4 || rr) $fatal(1,"ARMv4 mode or reset replacement policy wrong");
      issue(32'hee010f10,32'h00001272); read_control();
      if ((captured & 32'h00000c00) !== 0) $fatal(1,"reserved bits 11:10 must read zero: %h",captured);
      if (!l4) $fatal(1,"firmware control write disabled ARMv4 behavior");
      issue(32'hee010f10,32'h00004078); read_control();
      if (!(captured & 32'h4000) || !l4 || !rr) $fatal(1,"replacement bit must not change ARM version: %h",captured);
      dc_lock_done=0;
      fork
        begin issue(32'hee090f10,32'h14000000);end // MCR c9,c0,0: D base = 5
        begin
          wait(dc_lock);repeat(4) @(negedge clk);
          if(done || !dc_lock) $fatal(1,"lock update did not wait for cache");
          dc_lock_done=1;
        end
      join
      issue(32'hee090f30,32'h24000000); // MCR c9,c0,1: I base = 9
      issue(32'hee190f10,0);if(captured!==32'h14000000 || dc_base!==5)$fatal(1,"D lockdown readback %h",captured);
      issue(32'hee190f30,0);if(captured!==32'h24000000)$fatal(1,"I lockdown readback %h",captured);
      buffer_empty=0;
      fork
        begin issue(32'hee070f9a,0);end // MCR p15,0,r0,c7,c10,4
        begin
          wait(drain);repeat(4) @(negedge clk);
          if(done || !drain)$fatal(1,"drain did not wait for the buffer");
          buffer_empty=1;
        end
      join
      if (touched_cache) $fatal(1,"drain must not clean or invalidate cache");
      prefetch_done=0;
      fork
        begin issue(32'hee070f3d,32'h12345000);end // MCR c7,c13,1
        begin
          wait(prefetch);repeat(4) @(negedge clk);
          if(done || !prefetch)$fatal(1,"prefetch did not wait for the I-cache");
          prefetch_done=1;
        end
      join
      buffer_empty=0;
      fork
        begin issue(32'hee070f90,0);end // MCR p15,0,r0,c7,c0,4: WFI
        begin
          wait(drain);repeat(3) @(negedge clk);
          if(done || !drain)$fatal(1,"WFI did not drain first");
          buffer_empty=1;repeat(4) @(negedge clk);
          if(done || drain)$fatal(1,"WFI did not wait after draining");
          irq=1;repeat(5) @(negedge clk);irq=0;
        end
      join
      if(touched_cache)$fatal(1,"WFI changed cache contents");
      $display("PASS: ARM920 CP15 type, reset, reserved bits, ARMv4 mode and drain");$finish;
    end
endmodule
