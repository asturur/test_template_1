// SPDX-License-Identifier: GPL-3.0-or-later
// Exercise the real writeback/RF boundary, including its registered CP15 read.
module test;
logic clk=0,reset=1,valid=0,load=0,cp_en=0;
logic [5:0] rd[4],cp_addr=0,cp_wa=16,wa=0,wb=0;
logic [39:0] wc=0;
logic [31:0] da=0,db=0,dc=0,cp_data=0;
wire [31:0] data[4],cp_result;
logic [31:0] model[40],expected_cp;
logic [31:0] rng=32'hf0159857;
integer checks=0,enabled=0,disabled=0,collisions=0;
zap_writeback #(.PHY_REGS(40),.BP_ENTRIES(4),.CPSR_INIT(32'hd3)) dut(
 .i_clk(clk),.i_reset(reset),.i_valid(valid),.i_code_stall(1'b1),
 .i_decompile('0),.i_decompile_valid(1'b0),.i_uop_last(1'b0),
 .i_cpu_pid(7'd0),.i_l4_enable(1'b1),.i_clear_btb(1'b0),
 .i_clear_from_alu(1'b0),.i_pc_from_alu(32'd0),.i_clear_from_decode(1'b0),
 .i_pc_from_decode(32'd0),.i_clear_from_icache(1'b0),.i_confirm_from_alu(1'b0),
 .i_alu_pc_ff(32'd0),.i_taken(2'd0),.i_mode16(1'b0),
 .i_irq(1'b0),.i_fiq(1'b0),.i_instr_abt(1'b0),.i_data_abt(2'd0),.i_swi(1'b0),.i_und(1'b0),
 .i_pc_plus_8_buf_ff(32'd8),.i_flags(32'hd3),
 .i_rd_index_0(rd[0]),.i_rd_index_1(rd[1]),.i_rd_index_2(rd[2]),.i_rd_index_3(rd[3]),
 .i_mem_load_ff(load),.i_wr_index(wa),.i_wr_data(da),.i_wr_index_1(wb),.i_wr_data_1(db),
 .i_wr_index_2(wc),.i_wr_data_2(dc),
 .i_copro_reg_en(cp_en),.i_copro_reg_rd_index(cp_addr),
 .i_copro_reg_wr_index(cp_wa),.i_copro_reg_wr_data(cp_data),
 .o_copro_reg_rd_data_ff(cp_result),
 .o_rd_data_0(data[0]),.o_rd_data_1(data[1]),.o_rd_data_2(data[2]),.o_rd_data_3(data[3]));
function automatic [31:0] random_word();
 rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);return rng;
endfunction

task automatic tick;
 #1;
 if(!reset)begin
  for(integer p=0;p<4;p++)if(data[p]!==model[rd[p]])$fatal(1,"CP15 changed normal read port%0d",p);
  if(dut.copro_rd_data!==model[cp_addr])$fatal(1,"dedicated CP15 read");
  expected_cp=model[cp_en ? cp_addr : rd[0]];
  // Expected pre-edge response deliberately excludes current synchronous writes.
  // The same physical RF still applies B>A and then background C on this edge.
  if(cp_en)begin model[cp_wa]=cp_data;model[16]=0;enabled++;end
  else if(valid)begin model[wa]=da;model[load?wb:16]=db;disabled++;end
  for(integer r=0;r<40;r++)if(wc[r])model[r]=dc;
  if(valid && load && wa==wb && wc[wa])collisions++;
 end else for(integer r=0;r<40;r++)model[r]=0;
 clk=1;#1;clk=0;
 if(!reset && cp_result!==expected_cp)$fatal(1,"registered CP15 response or same-edge read/write priority");
 checks++;
endtask
initial begin
 for(integer p=0;p<4;p++)rd[p]=0;
 tick();reset=0;
 for(integer r=0;r<40;r++)begin wc=40'b1<<r;dc=random_word();tick();end
 wc=0;
 // Independent normal/CP addresses, enabled and disabled response semantics,
 // every physical register and coincident A/B/C write/read collisions.
 for(integer r=0;r<40;r++)for(integer c=0;c<40;c++)for(integer mode=0;mode<8;mode++)begin
  for(integer p=0;p<4;p++)rd[p]=6'((r+p*7)%40);
  cp_addr=6'(c);cp_en=mode[0];valid=1;load=mode[1];
  wa=6'(r);wb=wa;cp_wa=cp_addr;wc=mode[2] ? (40'b1<<r)|(40'b1<<c) : 0;
  da=random_word();db=random_word();dc=random_word();cp_data=random_word();tick();
 end
 // Hold/poison the source selection across resets; no extra response edge.
 for(integer n=0;n<1000;n++)begin
  reset=n%97==0;cp_en=n[0];valid=n[1];load=n[2];wc=n[3]?40'hfffffffff:0;
  for(integer p=0;p<4;p++)rd[p]=6'(random_word()%40);
  cp_addr=6'(random_word()%40);wa=6'(random_word()%40);wb=6'(random_word()%40);cp_wa=6'(random_word()%40);
  da=random_word();db=random_word();dc=random_word();cp_data=random_word();tick();
 end
 if(enabled<6000 || disabled<6000 || collisions<1000)$fatal(1,"CP15 RF coverage");
 $display("PASS: independent CP15 RF ownership %0d clocks, enabled=%0d disabled=%0d collisions=%0d",checks,enabled,disabled,collisions);$finish;
end
endmodule
