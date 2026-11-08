// SPDX-License-Identifier: GPL-3.0-or-later
// Independent register-file scoreboard and priority oracle. Exercise the actual
// four asynchronous read ports through issue and its existing output registers.
module test;
logic clk=0, reset=0, wen=0, data_stall=0, shift_stall=0, clear_wb=0, clear_alu=0;
logic mem_load=0, mem_store=0, align_pc=0;
logic [5:0] wa=0, wb=0;
logic [39:0] wc=0;
logic [31:0] da=0, db=0, dc=0, pc=32'h1234567b, cpsr=32'hd00000d3;
logic [32:0] index[4];
logic [5:0] dest[6];
logic [5:0] valid=0;
logic [31:0] value[6];
wire [31:0] rd_data[4];
logic [31:0] model[40];
logic [31:0] expected[4], held[4];
wire [31:0] nxt[4], result[4];
integer checks=0;
logic [31:0] rng=32'h762c19a5;
function automatic [31:0] random_word();
 rng = (rng ^ (rng << 13)); rng = (rng ^ (rng >> 17)); rng = (rng ^ (rng << 5));
 return rng;
endfunction
zap_register_file rf(.i_clk(clk),.i_reset(reset),.i_wen(wen),
 .i_wr_addr_a(wa),.i_wr_addr_b(wb),.i_wr_addr_c(wc),
 .i_wr_data_a(da),.i_wr_data_b(db),.i_wr_data_c(dc),
 .i_rd_addr_a(index[0][5:0]),.i_rd_addr_b(index[1][5:0]),
 .i_rd_addr_c(index[2][5:0]),.i_rd_addr_d(index[3][5:0]),
 .o_rd_data_a(rd_data[0]),.o_rd_data_b(rd_data[1]),
 .o_rd_data_c(rd_data[2]),.o_rd_data_d(rd_data[3]));
zap_issue_main issue(
 .i_clk(clk),
 .i_reset(reset),
 .i_uop_last('0),
 .i_swp_tag('0),
 .i_cpu_mode(cpsr),
 .i_clear_from_writeback(clear_wb),
 .i_data_stall(data_stall),
 .i_clear_from_alu(clear_alu),
 .i_stall_from_shifter(shift_stall),
 .i_pc_plus_8_ff(pc),
 .i_pc_ff('0),
 .i_switch_ff('0),
 .i_taken_ff('0),
 .i_ppc_ff('0),
 .i_decompile('0),
 .i_condition_code_ff(4'hf),
 .i_destination_index_ff('0),
 .i_alu_source_ff(index[0]),
 .i_alu_operation_ff('0),
 .i_shift_source_ff(index[1]),
 .i_shift_operation_ff('0),
 .i_shift_length_ff(index[2]),
 .i_flag_update_ff('0),
 .i_mem_srcdest_index_ff(index[3][5:0]),
 .i_mem_load_ff(mem_load),
 .i_mem_store_ff(mem_store),
 .i_mem_pre_index_ff('0),
 .i_mem_unsigned_byte_enable_ff('0),
 .i_mem_signed_byte_enable_ff('0),
 .i_mem_signed_halfword_enable_ff('0),
 .i_mem_unsigned_halfword_enable_ff('0),
 .i_mem_translate_ff('0),
 .i_irq_ff('0),
 .i_fiq_ff('0),
 .i_abt_ff('0),
 .i_swi_ff('0),
 .i_und_ff('0),
 .i_force32align_ff(align_pc),
 .i_dc_lock('0),
 .i_rd_data_0(rd_data[0]),
 .i_rd_data_1(rd_data[1]),
 .i_rd_data_2(rd_data[2]),
 .i_rd_data_3(rd_data[3]),
 .i_shifter_destination_index_ff(dest[0]),
 .i_alu_destination_index_ff(dest[1]),
 .i_postalu0_destination_index_ff(dest[2]),
 .i_postalu1_destination_index_ff(dest[3]),
 .i_postalu_destination_index_ff(dest[4]),
 .i_memory_destination_index_ff(dest[5]),
 .i_shifter_dav_ff('0),
 .i_alu_dav_nxt(valid[0]),
 .i_alu_dav_ff(valid[1]),
 .i_postalu0_dav_ff(valid[2]),
 .i_postalu1_dav_ff(valid[3]),
 .i_postalu_dav_ff(valid[4]),
 .i_memory_dav_ff(valid[5]),
 .i_alu_destination_value_nxt(value[0]),
 .i_alu_destination_value_ff(value[1]),
 .i_postalu0_destination_value_ff(value[2]),
 .i_postalu1_destination_value_ff(value[3]),
 .i_postalu_destination_value_ff(value[4]),
 .i_memory_destination_value_ff(value[5]),
 .i_shifter_mem_srcdest_index_ff('0),
 .i_alu_mem_srcdest_index_ff('0),
 .i_postalu0_mem_srcdest_index_ff('0),
 .i_postalu1_mem_srcdest_index_ff('0),
 .i_postalu_mem_srcdest_index_ff('0),
 .i_memory_mem_srcdest_index_ff('0),
 .i_shifter_mem_load_ff('0),
 .i_alu_mem_load_ff('0),
 .i_postalu0_mem_load_ff('0),
 .i_postalu1_mem_load_ff('0),
 .i_postalu_mem_load_ff('0),
 .i_memory_mem_load_ff('0)
);

assign nxt[0]=issue.o_alu_source_value_nxt;
assign nxt[1]=issue.o_shift_source_value_nxt;
assign nxt[2]=issue.o_shift_length_value_nxt;
assign nxt[3]=issue.o_mem_srcdest_value_nxt;
assign result[0]=issue.o_alu_source_value_ff;
assign result[1]=issue.o_shift_source_value_ff;
assign result[2]=issue.o_shift_length_value_ff;
assign result[3]=issue.o_mem_srcdest_value_ff;
function automatic [31:0] oracle(input integer port_no);
 logic [32:0] idx;
 logic [31:0] answer;
 bit found;
 idx=index[port_no];
 answer=model[idx[5:0]];
 // Walk oldest to newest so each younger valid match overwrites the result.
 for(integer stage=5;stage>=0;stage--)
  if(valid[stage] && dest[stage]==idx[5:0]) answer=value[stage];
 case(idx[5:0])
  6'd17: answer=cpsr;
  6'd15: answer=pc;
  6'd16: answer=0;
 endcase
 if(idx[32]) answer=idx[31:0];
 if(port_no==0 && align_pc && !mem_load && !mem_store) answer[1:0]=0;
 return answer;
endfunction

task automatic tick;
 #2; clk=1;
 if(reset) for(integer r=0;r<40;r++) model[r]=0;
 else begin
  if(wen) begin model[wa]=da; model[wb]=db; end
  for(integer r=0;r<40;r++) if(wc[r]) model[r]=dc;
 end
 #2; clk=0;
endtask

task automatic check_cycle;
 #1;
 for(integer p=0;p<4;p++) begin
  if(index[p][5:0]<40 && rd_data[p]!==model[index[p][5:0]])
   $fatal(1,"RF port %0d index %0d",p,index[p][5:0]);
  expected[p]=oracle(p);
  if(nxt[p]!==expected[p]) $fatal(1,"operand port %0d idx %h valid %h got %h expected %h",p,index[p],valid,nxt[p],expected[p]);
  held[p]=result[p];
 end
 tick();
 if(!reset && !clear_wb && !clear_alu) for(integer p=0;p<4;p++)
  if(result[p] !== ((data_stall || shift_stall) ? held[p] : expected[p]))
   $fatal(1,"issue register/stall port %0d",p);
 if((reset || clear_wb || clear_alu) && (issue.o_condition_code_ff!==4'hf || issue.o_swp_tag!==0))
  $fatal(1,"issue reset/clear validity");
 checks++;
endtask

initial begin
 for(integer p=0;p<4;p++) index[p]=0;
 for(integer stage=0;stage<6;stage++) begin dest[stage]=0;value[stage]=32'h10203041*(stage+1);end
 reset=1;tick();reset=0;
 // Seed every physical register, including all banked registers and SPSRs.
 wen=1;
 for(integer r=0;r<40;r++) begin wa=6'(r);wb=6'(r);da=random_word();db=random_word();check_cycle();end
 wen=0;
 // Every validity combination with all stages matching, plus immediate and
 // PC/CPSR/RAZ override collisions. Check every physical read port/address.
 for(integer r=0;r<40;r++) for(integer mask=0;mask<64;mask++) begin
  for(integer p=0;p<4;p++) index[p]=33'(r);
  for(integer stage=0;stage<6;stage++) dest[stage]=6'(r);
  valid=6'(mask);align_pc=mask[0];mem_load=mask[1];mem_store=mask[2];
  check_cycle();
  for(integer p=0;p<3;p++) index[p][32]=1;
  check_cycle();
 end
 // Independent ports, partial matches, changing operands and write collisions.
 for(integer cycle=0;cycle<12000;cycle++) begin
  for(integer p=0;p<4;p++) begin index[p]={1'b0,random_word()};index[p][5:0]=6'(random_word()%40);end
  for(integer p=0;p<3;p++) index[p][32]=(random_word()%4)==0;
  for(integer stage=0;stage<6;stage++) begin dest[stage]=6'(random_word()%40);value[stage]=random_word();end
  valid=6'(random_word());wen=1'(random_word());
  wa=6'(random_word()%40);wb=(cycle%3==0)?wa:6'(random_word()%40);
  wc=40'(random_word())<<8; if(cycle%4==0) wc[wb]=1;
  da=random_word();db=random_word();dc=random_word();
  data_stall=(cycle%7==0);shift_stall=(cycle%11==0);
  clear_wb=(cycle%101==0);clear_alu=(cycle%103==0);reset=(cycle%997==0);
  align_pc=1'(random_word());mem_load=1'(random_word());mem_store=1'(random_word());
  check_cycle();
 end
 $display("PASS: operand oracle %0d cycles; 40 physical registers, all forwarding priorities, immediate/PC/CPSR/RAZ, write collisions, stalls/reset/clear",checks);
 $finish;
end
endmodule
