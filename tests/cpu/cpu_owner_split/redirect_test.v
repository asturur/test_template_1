`timescale 1ns/1ps
module test;
  reg clk=0,reset=1,stall=0,aclr=0,dclr=0,thumb=0;
  reg irq=0,fiq=0,pabt=0,swi=0,und=0,valid=0,loadpc=0;
  reg [1:0] dabt=0;
  reg [5:0] index1=16;
  reg [31:0] atarget=0,dtarget=0,data1=0;
  reg [6:0] pid=0;
  integer checks=0,k;
  reg [32:0] old_packet;
  always #5 clk=~clk;
  zap_writeback #(.BP_ENTRIES(16)) dut (
    .i_decompile('0),
    .i_decompile_valid('0),
    .i_uop_last('0),
    .o_decompile(),
    .o_shelve(),
    .i_cpu_pid(pid),
    .i_l4_enable('0),
    .i_clear_btb('0),
    .i_clk(clk),
    .i_reset(reset),
    .i_valid(valid),
    .i_code_stall(stall),
    .i_clear_from_alu(aclr),
    .i_pc_from_alu(atarget),
    .i_clear_from_decode(dclr),
    .i_pc_from_decode(dtarget),
    .i_clear_from_icache('0),
    .i_confirm_from_alu('0),
    .i_alu_feedback_valid('0),
    .i_alu_pc_ff('0),
    .i_taken('0),
    .i_rd_index_0('0),
    .i_rd_index_1('0),
    .i_rd_index_2('0),
    .i_rd_index_3('0),
    .i_mem_load_ff(loadpc),
    .i_wr_index('0),
    .i_wr_data('0),
    .i_flags('0),
    .i_wr_index_1(index1),
    .i_wr_data_1(data1),
    .i_wr_index_2('0),
    .i_wr_data_2('0),
    .i_mode16(thumb),
    .i_irq(irq),
    .i_fiq(fiq),
    .i_instr_abt(pabt),
    .i_data_abt(dabt),
    .i_swi(swi),
    .i_und(und),
    .i_pc_plus_8_buf_ff('0),
    .i_copro_reg_en('0),
    .i_copro_reg_wr_index('0),
    .i_copro_reg_rd_index('0),
    .i_copro_reg_wr_data('0),
    .o_copro_reg_rd_data_ff(),
    .o_rd_data_0(),
    .o_rd_data_1(),
    .o_rd_data_2(),
    .o_rd_data_3(),
    .o_rf_wen(),
    .o_rf_wr_addr_a(),
    .o_rf_wr_addr_b(),
    .o_rf_wr_data_a(),
    .o_rf_wr_data_b(),
    .o_pc(),
    .o_pc_check(),
    .o_pc_nxt(),
    .o_taken(),
    .o_pred(),
    .o_cpsr_nxt(),
    .o_clear_from_writeback(),
    .o_wb_stb(),
    .o_wb_cyc(),
    .o_trace(),
    .o_trace_valid(),
    .o_trace_uop_last()
  );
  task tick;begin @(posedge clk);#1;@(negedge clk);#1;end endtask
  task fresh;
    begin
      reset=1;aclr=0;dclr=0;stall=0;irq=0;fiq=0;pabt=0;swi=0;und=0;
      dabt=0;valid=0;loadpc=0;pid=0;thumb=0;tick();reset=0;repeat(4)tick();
      if(!dut.o_wb_stb)$fatal(1,"old fetch not established");
    end
  endtask
  task park;
    input [31:0] target;
    input decode;
    begin
      stall=1;atarget=target;dtarget=target;aclr=!decode;dclr=decode;
      old_packet=dut.pc_del3_ff;
      repeat(3)begin
        tick();
        if(dut.pc_del3_ff!==old_packet || !dut.shelve_ff || dut.pc_shelve_ff!==target)
          $fatal(1,"redirect changed held old fetch or target owner");
      end
    end
  endtask
  task repeated;
    input [31:0] target,expected;
    input decode,tmode;
    input [6:0] context_pid;
    begin
      fresh();thumb=tmode;pid=context_pid;park(target,decode);
      stall=0;tick();
      if(dut.pc_del_ff!=={1'b1,expected} || dut.pc_del2_ff[32] || dut.pc_del3_ff[32] || dut.shelve_ff)
        $fatal(1,"registered target was not handed off once");
      aclr=0;dclr=0;tick();tick();
      if(!dut.o_wb_stb || dut.o_pc!==expected)$fatal(1,"wrong first target fetch");
      stall=1;old_packet=dut.pc_del3_ff;repeat(3)begin tick();if(dut.pc_del3_ff!==old_packet)$fatal(1,"new target changed while stalled");end
      stall=0;tick();
      $display("REDIRECT_SEQUENCE raw=%h mapped=%h next=%h expected_next=%h",target,expected,dut.o_pc,expected+(tmode?2:4));
      if(!dut.o_wb_stb || dut.o_pc!==expected+(tmode?2:4))$fatal(1,"target replayed or next instruction skipped");
      tick();if(dut.o_pc!==expected+(tmode?4:8))$fatal(1,"wrong second sequential fetch");
      checks=checks+1;
    end
  endtask
  task ended;
    input decode;
    begin
      fresh();park(32'h80003210,decode);aclr=0;dclr=0;
      repeat(2)begin tick();if(!dut.shelve_ff || dut.pc_del3_ff!==old_packet)$fatal(1,"ended redirect lost pending owner");end
      stall=0;tick();
      if(dut.pc_del_ff!==33'h180003210 || dut.shelve_ff)$fatal(1,"ended strobe did not hand off saved target");
      tick();tick();if(!dut.o_wb_stb || dut.o_pc!==32'h80003210)$fatal(1,"ended redirect wrong target");
      tick();if(dut.o_pc!==32'h80003214)$fatal(1,"ended redirect target replay");
      checks=checks+1;
    end
  endtask
  task direct;
    input [31:0] target,expected;
    input decode,tmode;
    input [6:0] context_pid;
    begin
      fresh();thumb=tmode;pid=context_pid;atarget=target;dtarget=target;
      aclr=!decode;dclr=decode;tick();
      if(dut.pc_del_ff!=={1'b1,expected} || dut.pc_del2_ff[32] || dut.pc_del3_ff[32] || dut.shelve_ff)
        $fatal(1,"first ready registered CPU target not handed off directly");
      aclr=0;dclr=0;tick();tick();
      if(!dut.o_wb_stb || dut.o_pc!==expected)$fatal(1,"immediate target state/canonical/FCSE");
      stall=1;old_packet=dut.pc_del3_ff;
      repeat(3)begin tick();if(dut.pc_del3_ff!==old_packet)$fatal(1,"immediate target changed while held");end
      stall=0;tick();
      if(dut.o_pc!==expected+(tmode?2:4))$fatal(1,"immediate target successor replay/skip");
      checks=checks+1;
      $display("REDIRECT_IMMEDIATE raw=%h expected=%h decode=%0d thumb=%0d PID=%0d",target,expected,decode,tmode,context_pid);
    end
  endtask
  initial begin
    direct(32'h80004444,32'h80004444,0,0,0);
    direct(32'h80004444,32'h80004444,1,0,0);
    direct(32'h80004447,32'h80004446,0,1,0);
    direct(32'h80004447,32'h80004446,1,1,0);
    direct(32'h00101234,32'h0a101234,1,0,5);
    direct(32'h01fffffc,32'h0bfffffc,0,0,5);
    $display("REDIRECT_CASE first_ready_CPU_target ARM_Thumb_FCSE_carry held_successor PASS");
    ended(0);ended(1);
    $display("REDIRECT_CASE strobe_ended_before_drain ALU_decode saved_owner PASS");
    repeated(32'h80001234,32'h80001234,0,0,0);
    repeated(32'h80002234,32'h80002234,1,0,0);
    repeated(32'h80001236,32'h80001236,0,1,0);
    repeated(32'h00101234,32'h0a101234,0,0,5);
    repeated(32'h01fffffc,32'h0bfffffc,0,0,5);
    $display("REDIRECT_CASE registered_ALU_decode ARM_Thumb FCSE held_fetch unique_target_and_successors PASS");
    fresh();park(32'h80001234,0);atarget=32'h80005678;stall=0;tick();
    if(dut.pc_del_ff!==33'h180005678 || dut.shelve_ff)$fatal(1,"changed target did not hand off actual current target");
    aclr=0;repeat(2)tick();if(!dut.o_wb_stb || dut.o_pc!==32'h80005678)$fatal(1,"changed target lost");checks=checks+1;
    $display("REDIRECT_CASE changed_target no_stale_handoff PASS");
    // Higher priority writeback events must retain the existing vector/PC-load path.
    for(k=0;k<7;k=k+1)begin
      fresh();park(32'h80001234,0);stall=0;
      case(k)
        0:dabt=1;
        1:fiq=1;
        2:irq=1;
        3:pabt=1;
        4:swi=1;
        5:und=1;
        6:begin valid=1;loadpc=1;index1=15;data1=32'h8000a000;end
      endcase
      #1;
      if(dut.pc_del_nxt[32])$fatal(1,"CPU handoff outranked older fault/interrupt/load-PC");
      case(k)
        0:if(dut.pc_nxt[31:0]!==32'h10)$fatal(1,"DABT vector");
        1:if(dut.pc_nxt[31:0]!==32'h1c)$fatal(1,"FIQ vector");
        2:if(dut.pc_nxt[31:0]!==32'h18)$fatal(1,"IRQ vector");
        3:if(dut.pc_nxt[31:0]!==32'h0c)$fatal(1,"PABT vector");
        4:if(dut.pc_nxt[31:0]!==32'h08)$fatal(1,"SWI vector");
        5:if(dut.pc_nxt[31:0]!==32'h04)$fatal(1,"UND vector");
        6:if(dut.pc_nxt[31:0]!==32'h8000a000)$fatal(1,"load-PC target");
      endcase
      tick();checks=checks+1;
    end
    $display("REDIRECT_CASE DABT_FIQ_IRQ_PABT_SWI_UND_loadPC_priority PASS");
    fresh();park(32'h80001234,0);irq=1;tick();irq=0;aclr=0;stall=0;tick();
    if(dut.pc_del_ff!==33'h100000018 || dut.shelve_ff)$fatal(1,"pending IRQ did not replace older target");
    tick();tick();if(dut.o_pc!==32'h18)$fatal(1,"stale old target after pending IRQ");checks=checks+1;
    $display("REDIRECT_CASE pending_IRQ_replaces_saved_CPU_target PASS");
    fresh();park(32'h80001234,0);reset=1;aclr=0;stall=0;tick();reset=0;repeat(4)tick();
    if(dut.shelve_ff || dut.o_pc==32'h80001234)$fatal(1,"stale redirect survived reset");checks=checks+1;
    $display("REDIRECT_CASE reset_cancels_pending_target PASS");
    $display("PASS redirect_handoff checks=%0d",checks);$finish;
  end
  initial begin #100000;$fatal(1,"timeout");end
endmodule
