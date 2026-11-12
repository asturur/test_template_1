`timescale 1ns/1ps
module tb;
parameter INVERTED_CLOCK=0, CAPTURE_NEGEDGE=0,LINE_REFILL=0,SHORT_READS=0;
parameter real CLOCK_PIN_DELAY=0.0;
parameter integer SYS_CLK_HZ=104000000;
localparam real HALF_PERIOD=500000000.0/SYS_CLK_HZ;
reg clk=0; always #(HALF_PERIOD) clk=~clk;
wire memclk;
generate if(INVERTED_CLOCK) begin : inverted_clock
 wire pin_clock;
 ngage_sdram_clock forward_clock(.clk(clk),.sdram_clk(pin_clock));
 assign #(CLOCK_PIN_DELAY) memclk=pin_clock;
end else begin : shifted_clock
 reg pin_clock=0;
 initial begin #(1.5*HALF_PERIOD); forever #(HALF_PERIOD) pin_clock=~pin_clock; end
 assign memclk=pin_clock;
end endgenerate
reg rst=1, phone_reset=1, req=0, we=0; reg [24:0] addr=0; reg [31:0] din=0; reg [3:0] be=0;
wire ack, scrub_done, init; wire [31:0] dout; wire [21:0] ba_addr; wire [15:0] ba_din, ba_dout; wire [1:0] ba_dsn;
wire [3:0] rd,wr,ba_ack,ba_rdy,ba_dst,ba_dok; wire rfsh; tri [15:0] dq; wire [12:0] a; wire [1:0] bank; wire dqml,dqmh,nwe,ncas,nras,ncs,cke;
reg line_req=0;reg [24:0] line_addr=0;
wire line_ready,line_valid,line_last;wire [15:0] line_data;wire [1:0] ba_line;
wire owner_ready;
wire mreq,mwe,mack; wire [24:0] maddr; wire [31:0] mdata,mrdata; wire [3:0] mbe;
reg dma_req=0, dma_we=0, cpu_lock=0; reg [24:0] dma_addr=0; reg [31:0] dma_data=0; reg [3:0] dma_be=0; wire dma_ack; wire [31:0] dma_rdata;
wire routed_req,routed_we,routed_ack,dma_error;
wire [24:0] routed_addr;
wire [31:0] routed_data,routed_rdata;
wire [3:0] routed_be;
ngage_dma_route #(.LOCAL_ENABLE(0)) route (
 .clk(clk),.reset(phone_reset),.cpu_lock(cpu_lock),.cmd_valid(dma_req),.cmd_ready(),
 .cmd_write(dma_we),.cmd_addr({8'h0a,dma_addr[23:0]}),.cmd_data(dma_data),.cmd_be(dma_be),
 .rsp_valid(dma_ack),.rsp_error(dma_error),.rsp_data(dma_rdata),
 .ram_req(routed_req),.ram_write(routed_we),.ram_addr(routed_addr),.ram_data(routed_data),
 .ram_be(routed_be),.ram_ack(routed_ack),.ram_rdata(routed_rdata),
 .local_valid(),.local_ready(1'b0),.local_write(),.local_addr(),.local_data(),
 .local_be(),.local_done(1'b0),.local_error(1'b0),.local_rdata(32'b0)
);
ngage_sdram_arbiter arb(clk,phone_reset,cpu_lock,req && owner_ready,we,addr,din,be,ack,dout,
 routed_req && owner_ready,routed_we,routed_addr,routed_data,routed_be,routed_ack,routed_rdata,mreq,mwe,maddr,mdata,mbe,mack,mrdata,,);
ngage_sdram_adapter #(.LINE_REFILL(LINE_REFILL),.RAM_BYTES(32),.REFRESH_PERIOD(250)) adapter(line_req,line_addr,line_ready,line_valid,line_data,line_last,ba_line,clk,rst,phone_reset,init,mreq,mwe,maddr,mdata,mbe,mack,mrdata,scrub_done,ba_addr,ba_din,ba_dsn,rd,wr,ba_ack,ba_dst,ba_rdy,ba_dout,rfsh,owner_ready);
jtframe_sdram64 #(.SHORT_READS(SHORT_READS),.DYNAMIC_LINE(1),.AW(22),.HF(1),.READ_CAPTURE_NEGEDGE(CAPTURE_NEGEDGE),.BA0_LEN(256),.BA1_LEN(256),.BA2_LEN(16),.BA3_LEN(16),.PROG_LEN(16),.BA0_WEN(1),.BA1_WEN(1)) ctrl(
 .line_read(ba_line),.rst(rst),.clk(clk),.init(init),.ba0_addr(ba_addr),.ba1_addr(ba_addr),.ba2_addr(22'b0),.ba3_addr(22'b0),
 .rd(rd),.wr(wr),.ba0_din(ba_din),.ba1_din(ba_din),.ba2_din(16'b0),.ba3_din(16'b0),
 .ba0_dsn(ba_dsn),.ba1_dsn(ba_dsn),.ba2_dsn(2'b11),.ba3_dsn(2'b11),
 .prog_en(1'b0),.prog_addr(22'b0),.prog_rd(1'b0),.prog_wr(1'b0),.prog_din(16'b0),.prog_dsn(2'b11),.prog_ba(2'b0),
 .prog_dst(),.prog_dok(),.prog_rdy(),.prog_ack(),.rfsh(rfsh),.ack(ba_ack),.dst(ba_dst),.dok(ba_dok),.rdy(ba_rdy),.dout(ba_dout),
 .sdram_dq(dq),.sdram_a(a),.sdram_dqml(dqml),.sdram_dqmh(dqmh),.sdram_ba(bank),.sdram_nwe(nwe),.sdram_ncas(ncas),.sdram_nras(nras),.sdram_ncs(ncs),.sdram_cke(cke));
mt48lc16m16a2 ram(.Clk(memclk),.Cke(cke),.Dq(dq),.Addr(a),.Ba(bank),.Cs_n(ncs),.Ras_n(nras),.Cas_n(ncas),.We_n(nwe),.Dqm({dqmh,dqml}),.downloading(1'b0),.VS(1'b0),.frame_cnt(32'b0));
integer line_bank;reg [24:0] line_base;
integer read_commands=0, before_reads=0,actual_read_beats=0;
always @(posedge memclk)begin #0.001;if(ram.Data_out_enable)actual_read_beats=actual_read_beats+1;end
always @(posedge memclk) if(!init && {ncs,nras,ncas,nwe}==4'b0101) read_commands=read_commands+1;
// Check pin-level command spacing as well as returned data. A logical line
// keeps one owner and both writes must use their own byte-enable pair.
integer pin_cycle=0, first_read_cycle=0, first_write_cycle=0;
integer write_commands=0;
`ifdef VERILATOR
wire [15:0] pin_write_data=ctrl.sdram_din;
`else
wire [15:0] pin_write_data=dq;
`endif
reg line_second=0, write_second=0;
reg [12:0] first_write_addr=0;
reg [1:0] first_write_bank=0;
always @(posedge memclk) begin
 pin_cycle=pin_cycle+1;
 if(!init && {ncs,nras,ncas,nwe}==4'b0101 && adapter.line_op) begin
  if(!line_second)first_read_cycle=pin_cycle;
  else if(pin_cycle-first_read_cycle!=8)$fatal(1,"line READ spacing %0d",pin_cycle-first_read_cycle);
  line_second=!line_second;
 end
 if(!init && {ncs,nras,ncas,nwe}==4'b0100) begin
  write_commands=write_commands+1;
  if(!write_second)begin
   first_write_cycle=pin_cycle;first_write_addr=a;first_write_bank=bank;
   if(pin_write_data!==adapter.data[15:0] || {dqmh,dqml}!==~adapter.mask[1:0])
    $fatal(1,"low WRITE payload/mask data=%h mask=%b",pin_write_data,{dqmh,dqml});
  end else begin
   if(pin_cycle-first_write_cycle!=1 || bank!==first_write_bank || a[8:0]!==first_write_addr[8:0]+9'd1)
    $fatal(1,"native word WRITE was not consecutive in one bank");
   if(pin_write_data!==adapter.data[31:16] || {dqmh,dqml}!==~adapter.mask[3:2])
    $fatal(1,"high WRITE payload/mask data=%h mask=%b",pin_write_data,{dqmh,dqml});
  end
  write_second=!write_second;
 end
end
integer acknowledgments=0, refreshes=0, count=0, i, before_ack;
always @(posedge clk) begin
 if(ack) acknowledgments<=acknowledgments+1;
 if(!init && {ncs,nras,ncas,nwe}==4'b0001) refreshes<=refreshes+1;
 if(acknowledgments==0 && ba_ack[0] && rd[0]) $display("TIMING ack=%0t",$time);
 if(acknowledgments==0 && ba_rdy[0] && !we && req) $display("TIMING rdy=%0t data=%h",$time,ba_dout);
end
integer before_beats;
integer short_checks=0, short_beats=0, short_wait=0;
integer write_checks=0, write_wait=0, before_writes=0, line_wait=0, line_clocks=0;
task transfer(input bit w,input [24:0] address,input [31:0] value,input [3:0] mask,input [31:0] expected);
 begin
 @(negedge clk);before_ack=acknowledgments;before_reads=read_commands;before_beats=actual_read_beats;before_writes=write_commands;we=w;addr=address;din=value;be=mask;req=1;
 count=0; while(!ack && count<3000) begin @(negedge clk);count=count+1; end
 if(!ack) $fatal(1,"timeout address %h",address);
 if(w)begin
  if(write_commands-before_writes!=2 || write_second)$fatal(1,"word did not finish exactly two WRITEs");
  write_checks=write_checks+1;write_wait=write_wait+count;
 end
 if(!w && read_commands!=before_reads+1) $fatal(1,"32-bit read issued %0d READ commands",read_commands-before_reads);
 if(!w && dout!==expected) $fatal(1,"read %h got %h expected %h",address,dout,expected);
 req=0;
 repeat(5) @(negedge clk);
 if(ack || acknowledgments != before_ack+1) $fatal(1,"duplicate or missing acknowledgement");
 req=0;repeat(3) @(negedge clk);
 if(LINE_REFILL && !w) begin
  if(actual_read_beats-before_beats!=(SHORT_READS?2:8))
   $fatal(1,"short request transferred %d halfwords",actual_read_beats-before_beats);
  short_checks=short_checks+1;short_beats=short_beats+actual_read_beats-before_beats;short_wait=short_wait+count;
 end
 end
endtask
initial begin
 repeat(5) @(negedge clk);rst=0;
 count=0;while(!scrub_done && count<15000) begin @(negedge clk);count=count+1; end
 if(!scrub_done) $fatal(1,"scrub timeout init=%b state=%d",init,adapter.state);
 phone_reset=0;
 transfer(0,0,0,15,0);
 transfer(1,0,32'h11223344,15,0);transfer(0,0,0,15,32'h11223344);
 transfer(1,0,32'haabbccdd,4'b0101,0);transfer(0,0,0,15,32'h11bb33dd);
 transfer(1,25'h7ffffc,32'h12345678,15,0); transfer(0,25'h7ffffc,0,15,32'h12345678);
 transfer(1,25'h800000,32'hfedcba98,15,0); transfer(0,25'h800000,0,15,32'hfedcba98);
 transfer(1,25'hfffffc,32'h0123abcd,15,0); transfer(0,25'hfffffc,0,15,32'h0123abcd);
 transfer(1,25'h3fc,32'h13579bdf,15,0); transfer(1,25'h400,32'h2468ace0,15,0);
 transfer(0,25'h3fc,0,15,32'h13579bdf); transfer(0,25'h400,0,15,32'h2468ace0);
 // Every byte-enable combination must update only the selected lanes.
 for(i=0;i<16;i=i+1) begin
   transfer(1,4,0,15,0); transfer(1,4,32'h89abcdef,i,0);
   transfer(0,4,0,15,((i&1)?32'h000000ef:0)|((i&2)?32'h0000cd00:0)|((i&4)?32'h00ab0000:0)|((i&8)?32'h89000000:0));
 end
 // Once captured, external request pins may change without changing the operation.
 @(negedge clk);req=1;we=1;addr=12;din=32'h10203040;be=15;
 @(negedge clk);addr=16;din=32'hffffffff;be=0;
 count=0;while(!ack && count<3000) begin @(negedge clk);count=count+1;end
 if(!ack) $fatal(1,"latched request timed out");
 req=0;repeat(4) @(negedge clk);transfer(0,12,0,15,32'h10203040);
 transfer(0,16,0,15,0);
 // Hold reset after a request has reached the controller: its completion
 // must be drained and not leak as an ACK into the next transaction.
 @(negedge clk);req=1;we=0;addr=0;be=15;
 wait(adapter.state==2); @(negedge clk);phone_reset=1;req=0;
 repeat(30) begin @(negedge clk);if(ack) $fatal(1,"stale ACK during reset");end
 phone_reset=0;transfer(0,0,0,15,32'h11bb33dd);
 // Release a short reset before the old SDRAM response arrives. A new
 // request may queue, but must never receive the old response or deadlock.
 @(negedge clk);req=1;we=0;addr=0;be=15;
 wait(adapter.state==2);@(negedge clk);phone_reset=1;req=0;
 @(negedge clk);phone_reset=0;req=1;addr=25'h800000;
 count=0;while(!ack && count<3000) begin @(negedge clk);count=count+1;end
 if(!ack || dout!==32'hfedcba98) $fatal(1,"short reset leaked stale read or deadlocked");
 req=0;repeat(5) @(negedge clk);
 // DMA stays blocked throughout an atomic CPU read/write reservation.
 @(negedge clk);cpu_lock=1;dma_req=1;dma_we=1;dma_addr=20;dma_data=32'h55aa55aa;dma_be=15;
 transfer(0,0,0,15,32'h11bb33dd);transfer(1,0,32'h99887766,15,0);
 if(dma_ack) $fatal(1,"DMA passed CPU lock");
 @(negedge clk);cpu_lock=0;count=0;
 while(!dma_ack && count<3000) begin @(negedge clk);count=count+1;end
 if(!dma_ack || dma_error) $fatal(1,"DMA routed write failed");
 dma_req=0;repeat(5) @(negedge clk);transfer(0,20,0,15,32'h55aa55aa);
 if(LINE_REFILL)begin
  // The CPU line register is represented by the consumer, not another adapter
  // cache. Two BL8 READ commands must stream exactly sixteen halfwords.
  for(line_bank=0;line_bank<4;line_bank=line_bank+1)begin
  case(line_bank)
   0:line_base=32;1:line_base=25'h800020;
   2:line_base=25'h7fffe0;default:line_base=25'hffffe0;
  endcase
  for(i=0;i<8;i=i+1)transfer(1,line_base+i*4,32'h90008000+i*32'h00010001,15,0);
  @(negedge clk);line_addr=line_base;line_req=1;before_reads=read_commands;
  wait(line_ready);@(negedge clk);line_req=0;count=0;line_clocks=0;
  while(count<16)begin
   @(negedge clk);line_clocks=line_clocks+1;
   if(count>0 && !line_valid)$fatal(1,"gap inside native line at halfword %0d",count);
   if(line_valid)begin
    if(line_data!==(count[0]?16'h9000:16'h8000)+(count/2))$fatal(1,"line half %d got %h",count,line_data);
    if(line_last!==(count==15))$fatal(1,"line last at %d",count);
    count=count+1;
   end
  end
  if(read_commands-before_reads!=2 || line_second)$fatal(1,"line did not use two BL8 reads");
  line_wait=line_wait+line_clocks;
  repeat(4)@(negedge clk);
  transfer(0,line_base+4,0,15,32'h90018001);
  if(line_bank==0)begin
   // Reset after the first physical data arrives, then queue a normal read
   // before the two-command line drain has finished.
   @(negedge clk);line_req=1;line_addr=line_base;
   wait(line_ready);@(negedge clk);line_req=0;
   wait(line_valid);@(negedge clk);phone_reset=1;
   repeat(2)@(negedge clk);phone_reset=0;req=1;we=0;addr=line_base+4;be=15;count=0;
   while(!ack && count<3000)begin @(negedge clk);count=count+1;if(line_valid)$fatal(1,"line beat escaped reset drain");end
   if(!ack || dout!==32'h90018001)$fatal(1,"line reset poisoned normal response");
   req=0;repeat(5)@(negedge clk);
  end
  end
 end
 // Keep the memory busy across many refresh intervals.
 for(i=0;i<80;i=i+1) begin transfer(1,8,i,15,0);transfer(0,8,0,15,i);end
 repeat(1500) @(negedge clk); if(refreshes<9) $fatal(1,"refresh not operating %d",refreshes);
 $display("BENCH native SDRAM writes=%0d write_wait_clocks=%0d four_line_wait_clocks=%0d",write_checks,write_wait,line_wait);
 $display("PASS SDRAM real controller and model, refreshes=%0d checked_short_reads=%0d halfwords=%0d wait_clocks=%0d",refreshes,short_checks,short_beats,short_wait);$finish;
end
initial begin #5000000; $fatal(1,"global timeout");end
endmodule
