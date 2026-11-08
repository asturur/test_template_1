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
integer checks=0, count=0, pushes=0, pops=0, full_pops=0, kills=0;
bit model_read_slot=0,model_write_slot=0;
bit exposed_known=0;
logic [31:0] exposed_pc;
integer physical_pushes[2]='{0,0},physical_pops[2]='{0,0};
logic [5:0] cp_index=0;
wire [31:0] cp_data;
logic [63:0] dc_lock=0;
logic [3:0] condition=14;
logic irq=0,fiq=0,abt=0,swi=0,und=0;
logic [1:0] swp=0;
logic last=0;
typedef struct packed {
 logic [131:0] indices;
 logic [31:0] pc;
 logic load, store, align_pc;
 logic [3:0] condition;
 logic irq,fiq,abt,swi,und,last;
 logic [1:0] swp;
} packet_t;
packet_t queue[2], incoming, head, physical_packet[2];
bit physical_known[2]='{0,0};
bit previous_kill=1,previous_wen=0;
logic [5:0] previous_wa=0,previous_wb=0;
logic [39:0] previous_wc=0;
integer owner_mask_checks[2]='{0,0};
integer source_wins[2][17];
logic [3:0] output_condition=15;
logic output_load=0;
logic [5:0] output_mem_index=0;
bit locked, pop, push, clear_packet;
function automatic bit source_locked(input logic [32:0] idx);
 return !idx[32] && idx[5:0]!=16 &&
  (dc_lock[idx[5:0]] || ((|dc_lock) && (head.irq || head.fiq || head.abt || head.swi || head.und)) ||
   (output_condition!=15 && output_load && output_mem_index==idx[5:0]));
endfunction
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
 .i_rd_addr_cp15(cp_index),.o_rd_data_cp15(cp_data),
 .o_rd_data_a(rd_data[0]),.o_rd_data_b(rd_data[1]),
 .o_rd_data_c(rd_data[2]),.o_rd_data_d(rd_data[3]));
zap_issue_main issue(
 .i_clk(clk),
 .i_reset(reset),
 .i_uop_last(last),
 .i_swp_tag(swp),
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
 .i_condition_code_ff(condition),
 .i_destination_index_ff(6'd16),
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
 .i_irq_ff(irq),
 .i_fiq_ff(fiq),
 .i_abt_ff(abt),
 .i_swi_ff(swi),
 .i_und_ff(und),
 .i_force32align_ff(align_pc),
 .i_dc_lock(dc_lock),
 .i_rf_wen(wen),.i_rf_wr_addr_a(wa),.i_rf_wr_addr_b(wb),.i_rf_wr_addr_c(wc),
 .i_rf_wr_data_a(da),.i_rf_wr_data_b(db),.i_rf_wr_data_c(dc),
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
 idx=head.indices[33*port_no+:33];
 answer=model[idx[5:0]];
 // Walk oldest to newest so each younger valid match overwrites the result.
 for(integer stage=5;stage>=0;stage--)
  if(valid[stage] && dest[stage]==idx[5:0]) answer=value[stage];
 case(idx[5:0])
  6'd17: answer=cpsr;
  6'd15: answer=head.pc;
  6'd16: answer=0;
 endcase
 if(idx[32]) answer=idx[31:0];
 if(port_no==0 && head.align_pc && !head.load && !head.store) answer[1:0]=0;
 return answer;
endfunction

// Independently reconstruct each physical owner's matches from captured test
// packets and the test's previous/current write events. Never read DUT pending
// selectors or classification bits to obtain the expected mask or winner.
task automatic check_owner_masks;
 for(integer bank=0;bank<2;bank++)if(physical_known[bank])for(integer p=0;p<4;p++)begin
  logic [32:0] idx;
  logic [15:0] expected_match,actual_matches;
  logic [16:0] grant,actual_grant;
  integer winner;
  idx=physical_packet[bank].indices[33*p+:33];
  expected_match=0;
  expected_match[0]=idx[32];expected_match[1]=idx[5:0]==16;
  expected_match[2]=idx[5:0]==15;expected_match[3]=idx[5:0]==17;
  for(integer stage=0;stage<6;stage++)expected_match[stage+4]=valid[stage] && dest[stage]==idx[5:0];
  expected_match[10]=idx[5:0]<40 && wc[idx[5:0]];
  expected_match[11]=wen && wb==idx[5:0];expected_match[12]=wen && wa==idx[5:0];
  if(!previous_kill)begin
   if(idx[5:0]<40 && previous_wc[idx[5:0]])expected_match[13]=1;
   else if(previous_wen && previous_wb==idx[5:0])expected_match[14]=1;
   else if(previous_wen && previous_wa==idx[5:0])expected_match[15]=1;
  end
  // Oldest-to-newest overwrite is independent of the RTL prefix mask tree.
  winner=16;
  for(integer candidate=15;candidate>=0;candidate--)if(expected_match[candidate])winner=candidate;
  grant=17'b1<<winner;
  actual_matches=bank ? issue.owner1_match[p] : issue.owner0_match[p];
  actual_grant=bank ? issue.owner1_select[p] : issue.owner0_select[p];
  if(actual_matches!==expected_match || actual_grant!==grant)
   $fatal(1,"owner mask bank=%0d port=%0d cycle=%0d match=%h/%h grant=%h/%h",bank,p,checks,actual_matches,expected_match,actual_grant,grant);
  if(model_read_slot==bank && issue.operand_select[p]!==grant)$fatal(1,"late owner grant selection");
  owner_mask_checks[bank]++;source_wins[bank][winner]++;
 end
endtask

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
 cp_index=6'((checks*7+3)%40);
 cpsr=cpsr^32'hf0000000; // Live flags change even while the packet is held.
 #1;
 clear_packet=reset || clear_wb || clear_alu;
 if(issue.o_stall_from_issue !== (count==2) || issue.o_operand_busy !== (count!=0))
  $fatal(1,"queue occupancy count=%0d full=%b busy=%b",count,issue.o_stall_from_issue,issue.o_operand_busy);
 for(integer p=0;p<4;p++) begin
  if(index[p][5:0]<40 && rd_data[p]!==model[index[p][5:0]])
   $fatal(1,"RF port %0d index %0d",p,index[p][5:0]);
  held[p]=result[p];
 end
 if(cp_data!==model[cp_index])$fatal(1,"independent CP15 RF read");
 if(issue.u_operand_read.read_slot!==model_read_slot || issue.u_operand_read.write_slot!==model_write_slot)
  $fatal(1,"physical FIFO pointer mismatch");
 if(!reset)check_owner_masks();
 // Representation invariant BEFORE this edge's writes: each valid packet's
 // raw base plus its own pending journal equals the independent architectural
 // RF. Check both owners, including reserve data before full-pop promotion.
 if(!reset)for(integer slot=0;slot<count;slot++)for(integer p=0;p<4;p++)begin
  logic [2:0] pending;
  logic [31:0] represented;
  integer physical;
  pending=(model_read_slot ^ (slot!=0)) ? issue.u_operand_read.slot1_pending[3*p+:3] : issue.u_operand_read.slot0_pending[3*p+:3];
  represented=(model_read_slot ^ (slot!=0)) ? issue.u_operand_read.slot1_data[32*p+:32] : issue.u_operand_read.slot0_data[32*p+:32];
  case(pending)
   0: begin end
   1: represented=issue.operand_commit_a;
   2: represented=issue.operand_commit_b;
   4: represented=issue.operand_commit_c;
   default: $fatal(1,"journal selector is not one-hot");
  endcase
  physical=queue[slot].indices[33*p+:6];
  if(physical<40 && represented!==model[physical])
   $fatal(1,"journal owner slot=%0d port=%0d index=%0d cycle=%0d got=%h expected=%h",slot,p,physical,checks,represented,model[physical]);
 end
 // Apply committed writes to an independent architectural RF scoreboard BEFORE
 // calculating this edge's issue result. No stored DUT operand is consulted.
 if(!reset)begin
  if(wen)begin model[wa]=da;model[wb]=db;end
  for(integer r=0;r<40;r++)if(wc[r])model[r]=dc;
 end
 head=queue[0];
 locked=0;
 if(count!=0 && head.condition!=15)
  for(integer p=0;p<4;p++)locked |= source_locked(head.indices[33*p+:33]);
 pop=count!=0 && !locked && !data_stall && !shift_stall;
 push=count<2 && !data_stall && !shift_stall &&
      (condition!=15 || irq || fiq || abt || swi || und);
 incoming.indices={index[3],index[2],index[1],index[0]};
 incoming.pc=pc;incoming.load=mem_load;incoming.store=mem_store;incoming.align_pc=align_pc;
 incoming.condition=condition;incoming.irq=irq;incoming.fiq=fiq;incoming.abt=abt;
 incoming.swi=swi;incoming.und=und;incoming.last=last;incoming.swp=swp;
 if(count!=0 && !reset)for(integer p=0;p<4;p++)begin
  expected[p]=oracle(p);
  if(nxt[p]!==expected[p])begin
   $display("DETAIL headidx=%h dutidx=%h base=%h raw=%h model=%h wen=%b wa=%d wb=%d wc=%h data=%h/%h/%h",head.indices[33*p+:33],issue.operand_mem_srcdest_index_ff,issue.operand_data[32*p+:32],issue.operand_data[32*p+:32],model[head.indices[33*p+:6]],wen,wa,wb,wc,da,db,dc);
   $fatal(1,"operand oracle port=%0d check=%0d count=%0d got=%h expected=%h",p,checks,count,nxt[p],expected[p]);end
 end
 if(!clear_packet && !data_stall && !shift_stall)begin
  output_condition=pop ? head.condition : 15;
  output_load=head.load;output_mem_index=head.indices[99+:6];
 end
 // Record physical capture with the pre-edge write pointer, independently
 // of logical head/pop updates below. Clear forbids new owner identity.
 if(push && !clear_packet)begin physical_packet[model_write_slot]=incoming;physical_known[model_write_slot]=1;end
 previous_kill=clear_packet;previous_wen=wen;
 previous_wa=wa;previous_wb=wb;previous_wc=wc;
 if(clear_packet)begin
  count=0;output_condition=15;kills++;
  if(reset)begin model_read_slot=0;exposed_known=0;end
  model_write_slot=model_read_slot;
 end
 else begin
  if(pop)begin physical_pops[model_read_slot]++;if(count==2)begin model_read_slot=!model_read_slot;full_pops++;end queue[0]=queue[1];count--;pops++;end
  if(push)begin if(count==0)model_read_slot=model_write_slot;physical_pushes[model_write_slot]++;model_write_slot=!model_write_slot;queue[count]=incoming;count++;pushes++;end
  if(count!=0)begin exposed_pc=queue[0].pc;exposed_known=1;end
 end
 tick();
 if(clear_packet && (issue.u_operand_read.slot0_pending!==0 || issue.u_operand_read.slot1_pending!==0 || issue.u_operand_read.read_slot!==model_read_slot || issue.u_operand_read.write_slot!==model_write_slot))$fatal(1,"kill left a physical pending owner");
 if(exposed_known && issue.operand_pc_plus_8_ff!==exposed_pc)$fatal(1,"empty/clear changed exposed packet PC");
 if(issue.o_condition_code_ff!==output_condition)$fatal(1,"issue condition check=%0d got=%h expected=%h",checks,issue.o_condition_code_ff,output_condition);
 if(!clear_packet)begin
  if(!data_stall && !shift_stall)begin
   if(pop)begin
    if(issue.o_pc_plus_8_ff!==head.pc)$fatal(1,"packet identity/order lost");
    for(integer p=0;p<4;p++)if(result[p]!==expected[p])$fatal(1,"issued value port=%0d check=%0d",p,checks);
    if({issue.o_irq_ff,issue.o_fiq_ff,issue.o_abt_ff,issue.o_swi_ff,issue.o_und_ff,issue.o_uop_last,issue.o_swp_tag}!==
       {head.irq,head.fiq,head.abt,head.swi,head.und,head.last,head.swp})$fatal(1,"owned exception/uop/SWP context");
   end else if({issue.o_irq_ff,issue.o_fiq_ff,issue.o_abt_ff,issue.o_swi_ff,issue.o_und_ff,issue.o_swp_tag}!==0)$fatal(1,"bubble exception");
  end else for(integer p=0;p<4;p++)if(result[p]!==held[p])$fatal(1,"issue hold");
 end else if({issue.o_irq_ff,issue.o_fiq_ff,issue.o_abt_ff,issue.o_swi_ff,issue.o_und_ff,issue.o_swp_tag}!==0)$fatal(1,"clear exception");
 if(push && !clear_packet)pc=pc+4; // Unique accepted identity; held D keeps it while full.
 checks++;
endtask

initial begin
 for(integer bank=0;bank<2;bank++)for(integer source=0;source<17;source++)source_wins[bank][source]=0;
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
  check_cycle(); check_cycle(); check_cycle();
  for(integer p=0;p<3;p++) index[p][32]=1;
  check_cycle(); check_cycle(); check_cycle();
 end
 // Fill under hazard, let writeback vanish while held, then full-pop/resume.
 clear_wb=1;check_cycle();clear_wb=0;
 for(integer p=0;p<4;p++)index[p]=7;
 mem_load=0;mem_store=0;valid=0;dc_lock=64'h80;
 check_cycle();check_cycle();
 wen=1;wa=7;wb=7;wc=40'h80;da=1;db=2;dc=32'hfedcba98;check_cycle();
 wen=0;wc=0;data_stall=1;repeat(20)check_cycle();data_stall=0;
 dc_lock=0;repeat(5)check_cycle();
 // Clear every occupied depth under both global holds, both redirect sources.
 for(integer occupancy=0;occupancy<3;occupancy++)for(integer clear_kind=0;clear_kind<2;clear_kind++)begin
  clear_wb=1;check_cycle();clear_wb=0;dc_lock=64'h80;
  repeat(occupancy)check_cycle();data_stall=1;shift_stall=1;
  clear_wb=!clear_kind;clear_alu=clear_kind;check_cycle();
  clear_wb=0;clear_alu=0;data_stall=0;shift_stall=0;dc_lock=0;
 end
 // NV-tagged exceptions still occupy and preserve all owned qualifiers.
 condition=15;irq=1;fiq=1;abt=1;swi=1;und=1;last=1;swp=3;
 repeat(4)check_cycle();
 condition=14;irq=0;fiq=0;abt=0;swi=0;und=0;last=0;swp=0;
 // Exhaust every pair of consecutive write-port masks for every physical
 // source, with capture, full hold, promotion, issue, kill and immediate reuse.
 // Different ports use adjacent indices to detect selector/owner interchange.
 valid=0;mem_load=0;mem_store=0;align_pc=0;
 for(integer r=0;r<40;r++)for(integer older=0;older<8;older++)for(integer newer=0;newer<8;newer++)begin
  clear_wb=1;wen=0;wc=0;dc_lock=0;check_cycle();clear_wb=0;
  for(integer p=0;p<4;p++)index[p]=33'((r+p)%40);
  dc_lock='1;check_cycle(); // Head acquisition.
  wa=6'(r);wb=6'(r);wen=(older&3)!=0;
  if(!(older&1))wa=6'((r+4)%40);
  if(!(older&2))wb=6'((r+5)%40);
  wc=(older&4)!=0 ? (40'b1<<r) : 0;
  da=random_word();db=random_word();dc=random_word();check_cycle(); // Reserve acquisition+commit.
  data_stall=1;
  wa=6'(r);wb=6'(r);wen=(newer&3)!=0;
  if(!(newer&1))wa=6'((r+4)%40);
  if(!(newer&2))wb=6'((r+5)%40);
  wc=(newer&4)!=0 ? (40'b1<<r) : 0;
  da=random_word();db=random_word();dc=random_word();check_cycle(); // Held consecutive commit.
  data_stall=0;dc_lock=0;
  da=random_word();db=random_word();dc=random_word();check_cycle(); // Full pop+current commit.
  wa=6'((r+1)%40);wb=wa;wc=40'b1<<wa;wen=1;
  da=random_word();db=random_word();dc=random_word();check_cycle(); // Promoted owner issue+commit.
  clear_alu=1;data_stall=1;check_cycle(); // Kill with journal data in flight.
  clear_alu=0;data_stall=0;wen=0;wc=0;
  for(integer p=0;p<4;p++)index[p]=33'((r+4+p)%40);
  check_cycle();check_cycle(); // Immediate reuse must ignore killed selectors.
 end
 // Both owner trees see every all-producer validity combination concurrently
 // with current C/B/A and a prior C journal. Include immediate low bits that
 // alias PC/RAZ/CPSR: immediate must win even though several class bits match.
 valid=0;mem_load=0;mem_store=0;align_pc=0;
 for(integer r=0;r<40;r++)for(integer immediate=0;immediate<2;immediate++)begin
  clear_wb=1;wen=0;wc=0;valid=0;dc_lock=0;check_cycle();clear_wb=0;
  for(integer p=0;p<4;p++)begin index[p]=33'(r);if(p<3)index[p][32]=1'(immediate);end
  dc_lock='1;check_cycle();check_cycle();
  wa=6'(r);wb=wa;wen=1;wc=40'b1<<r;
  for(integer stage=0;stage<6;stage++)dest[stage]=6'(r);
  valid=63;check_cycle();check_cycle();
  for(integer mask=63;mask>=0;mask--)begin valid=6'(mask);check_cycle();end
  wen=0;wc=0;check_cycle();check_cycle();dc_lock=0;check_cycle();
 end
 // Independent ports, partial matches, changing operands and write collisions.
 for(integer cycle=0;cycle<12000;cycle++) begin
  if(count<2 && !data_stall && !shift_stall)for(integer p=0;p<4;p++) begin index[p]={1'b0,random_word()};index[p][5:0]=6'(random_word()%40);end
  if(count<2 && !data_stall && !shift_stall)for(integer p=0;p<3;p++) index[p][32]=(random_word()%4)==0;
  for(integer stage=0;stage<6;stage++) begin dest[stage]=6'(random_word()%40);value[stage]=random_word();end
  valid=6'(random_word());wen=1'(random_word());
  wa=6'(random_word()%40);wb=(cycle%3==0)?wa:6'(random_word()%40);
  wc=40'(random_word())<<8; if(cycle%4==0) wc[wb]=1;
  da=random_word();db=random_word();dc=random_word();
  data_stall=(cycle%7==0);shift_stall=(cycle%11==0);
  clear_wb=(cycle%101==0);clear_alu=(cycle%103==0);reset=(cycle%997==0);
  if(count<2 && !data_stall && !shift_stall)begin
   align_pc=1'(random_word());mem_load=1'(random_word());mem_store=1'(random_word());
  end
  dc_lock=(cycle%17<8) ? 64'hff : 0;
  check_cycle();
 end
 if(full_pops<1 || pushes<500 || pops<500)$fatal(1,"coverage");
 if(physical_pushes[0]<500 || physical_pushes[1]<500 || physical_pops[0]<500 || physical_pops[1]<500)$fatal(1,"physical slot coverage");
 for(integer bank=0;bank<2;bank++)for(integer source=0;source<17;source++)
  if(source_wins[bank][source]==0)$fatal(1,"owner source coverage bank=%0d source=%0d",bank,source);
 $display("OWNER_MASKS: checks=%0d/%0d all17sources win in both physical owners",owner_mask_checks[0],owner_mask_checks[1]);
 $display("SLOTS: pushes=%0d/%0d pops=%0d/%0d",physical_pushes[0],physical_pushes[1],physical_pops[0],physical_pops[1]);
 $display("QUEUE: push=%0d pop=%0d full_pop=%0d kills=%0d",pushes,pops,full_pops,kills);
 $display("PASS: operand oracle %0d cycles; 40 physical registers, all forwarding priorities, immediate/PC/CPSR/RAZ, write collisions, stalls/reset/clear",checks);
 $finish;
end
endmodule
