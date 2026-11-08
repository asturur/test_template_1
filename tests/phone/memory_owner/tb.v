`timescale 1ns/1ps
// Reuse the explicit CPU stimulus stub from flash_reset/tb.v. This test forces
// the stable bridge request at the phone boundary, not any owner/decode state.
module memory_owner_tb;
 reg clk=0,rst=1,cold=1;
 always #5 clk=~clk;
 reg cyc=0,stb=0;
 reg [31:0] address=0;
 reg ram_done=0;
 wire init_done;
 integer checks=0;
 ngage_mister dut(.clk_sys(clk),.reset(rst),.cold_reset(cold),.sim_present(1'b0),
  .board_init_done(init_done),.sdram_dout(32'h12345678),.sdram_ack(ram_done),
  .ddram_dout(32'b0),.ddram_dout_ready(1'b0),.ddram_accept(1'b0),
  .debug_freeze_trace(1'b0),.keys(27'b0));
 task tick;begin @(negedge clk);#1;end endtask
 task read_memory;input [31:0] a;input [3:0] expected;input [31:0] result;
 begin
  tick();rst=1;cyc=0;stb=0;repeat(3)tick();rst=0;wait(!dut.core_reset);tick();
  address=a;cyc=1;stb=1;
  #1;if(dut.memory_req || dut.sdram_req || dut.flash_start)$fatal(1,"memory launched before capture");
  tick();
  if(!dut.memory_owned || dut.memory_owner!==expected)$fatal(1,"wrong region %h owner=%b",a,dut.memory_owner);
  // Deliberately poison unrelated live peripheral claims after acceptance.
  // A captured disjoint memory owner must ignore their data/ready/errors.
  force dut.brd_claim=1;force dut.dma_claim=1;
  force dut.brd_ready=1;force dut.brd_unmodeled=1;force dut.dma_bad=1;
  force dut.code_data=32'hc0decafe;force dut.user_data=32'habcdef01;
  #1;
  if(!dut.memory_req || dut.wb_ack || dut.wb_err || dut.diagnostic_fault)
   $fatal(1,"peripheral claim changed captured memory route %h",a);
  if(expected==1 && !dut.sdram_req)$fatal(1,"SDRAM blocked by peripheral claim");
  if(expected!=1 && !dut.flash_start)$fatal(1,"NOR blocked by peripheral claim");
  repeat(2)tick();
  if(dut.wb_err || dut.diagnostic_fault)$fatal(1,"peripheral error leaked into memory");
  if(expected==1)ram_done=1;
  else if(expected==4)begin force dut.user_rsp=1;force dut.user_err=0;end
  else begin force dut.code_rsp=1;force dut.code_err=0;end
  #1;if(!dut.wb_ack || dut.wb_dat_i!==result)$fatal(1,"memory response owner/data mismatch %h",a);
  cyc=0;stb=0;ram_done=0;tick();
  if(dut.memory_owner_valid || dut.memory_req)$fatal(1,"request gap retained old owner");
  release dut.brd_claim;release dut.dma_claim;release dut.brd_ready;
  release dut.brd_unmodeled;release dut.dma_bad;release dut.code_data;release dut.user_data;
  release dut.code_rsp;release dut.code_err;release dut.user_rsp;release dut.user_err;
  checks=checks+1;
 end endtask
 initial begin
  force dut.wb_cyc=cyc;force dut.wb_stb=stb;force dut.wb_adr=address;
  force dut.wb_we=0;force dut.wb_sel=15;
  // Isolate ownership from the NOR engines: inject return records below,
  // while full accepted DDR/drain protocol is checked by flash_reset.
  force dut.code_ready=0;force dut.user_ready=0;
  repeat(3)tick();cold=0;wait(init_done);tick();
  read_memory('h00000000,2,'hc0decafe);read_memory('h006ffffc,2,'hc0decafe);
  read_memory('h00700000,2,'hc0decafe);read_memory('h007efffc,2,'hc0decafe);
  read_memory('h007f0000,8,'hc0decafe);read_memory('h007ffffc,8,'hc0decafe);
  read_memory('h02000000,2,'hc0decafe);read_memory('h023ffffc,2,'hc0decafe);
  read_memory('h02400000,4,'habcdef01);read_memory('h027ffffc,4,'habcdef01);
  read_memory('h04000000,2,'hc0decafe);read_memory('h047ffffc,2,'hc0decafe);
  read_memory('h0a000000,1,'h12345678);read_memory('h0afffffc,1,'h12345678);
  tick();rst=1;repeat(3)tick();rst=0;wait(!dut.core_reset);tick();
  address='h10000000;cyc=1;stb=1;
  repeat(4)tick();if(dut.memory_req || dut.sdram_req || dut.flash_start ||
   !dut.wb_err || dut.diagnostic_reason!==2)$fatal(1,"unmapped access lost decode fault");
  cyc=0;stb=0;tick();
  $display("PASS captured memory ownership: %0d region endpoints, poisoned claims, held returns, gaps and unmapped fault",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"memory owner timeout");end
endmodule
