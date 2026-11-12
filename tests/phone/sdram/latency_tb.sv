// Matched physical-controller benchmark. NATIVE changes only bank service length.
// The legacy build substitutes saved pre-change adapter/controller/mux sources.
`timescale 1ns/1ps
module latency_tb;
parameter NATIVE=1;
parameter INVERTED_CLOCK=1, CAPTURE_NEGEDGE=1,LINE_REFILL=1,SHORT_READS=1;
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
`ifndef SDRAM_SHARED_PAYLOAD
assign owner_ready=1'b1;
`endif
wire mreq,mwe,mack; wire [24:0] maddr; wire [31:0] mdata,mrdata; wire [3:0] mbe;
reg cpu_lock=0;
wire routed_req,routed_we,routed_ack;
wire [24:0] routed_addr;
wire [31:0] routed_data,routed_rdata;
wire [3:0] routed_be;
reg lcd_req=0;
reg [24:0] lcd_addr=0;
wire lcd_ack, lcd_accept, dma_accept;
wire [31:0] lcd_data;
ngage_dma_ram_mux mux(
 .clk(clk),.reset(phone_reset),.lcd_req(lcd_req),.lcd_addr(lcd_addr),
 .lcd_accept(lcd_accept),.lcd_ack(lcd_ack),.lcd_rdata(lcd_data),
 .dma_req(1'b0),.dma_write(1'b0),.dma_addr(25'b0),.dma_data(32'b0),.dma_be(4'b0),
 .dma_ack(),.dma_rdata(),.mem_req(routed_req),.mem_write(routed_we),
 .mem_addr(routed_addr),.mem_data(routed_data),.mem_be(routed_be),
 .mem_accept(dma_accept),.mem_ack(routed_ack),.mem_rdata(routed_rdata));
ngage_sdram_arbiter arb(clk,phone_reset,cpu_lock,req && owner_ready,we,addr,din,be,ack,dout,
 routed_req && owner_ready,routed_we,routed_addr,routed_data,routed_be,routed_ack,routed_rdata,
 mreq,mwe,maddr,mdata,mbe,mack,mrdata,,dma_accept);
reg forced_refresh=0;
ngage_sdram_adapter #(.LINE_REFILL(LINE_REFILL),.RAM_BYTES(32),.REFRESH_PERIOD(1000000)) adapter(line_req,line_addr,line_ready,line_valid,line_data,line_last,ba_line,clk,rst,phone_reset,init,mreq,mwe,maddr,mdata,mbe,mack,mrdata,scrub_done,ba_addr,ba_din,ba_dsn,rd,wr,ba_ack,ba_dst,ba_rdy,ba_dout,rfsh
`ifdef SDRAM_SHARED_PAYLOAD
,owner_ready
`endif
);
jtframe_sdram64 #(.SHORT_READS(SHORT_READS),.DYNAMIC_LINE(1),.AW(22),.HF(1),.READ_CAPTURE_NEGEDGE(CAPTURE_NEGEDGE),.BA0_LEN(NATIVE?256:128),.BA1_LEN(NATIVE?256:128),.BA2_LEN(16),.BA3_LEN(16),.PROG_LEN(16),.BA0_WEN(1),.BA1_WEN(1)) ctrl(
 .line_read(ba_line),.rst(rst),.clk(clk),.init(init),.ba0_addr(ba_addr),.ba1_addr(ba_addr),.ba2_addr(22'b0),.ba3_addr(22'b0),
 .rd(rd),.wr(wr),.ba0_din(ba_din),.ba1_din(ba_din),.ba2_din(16'b0),.ba3_din(16'b0),
 .ba0_dsn(ba_dsn),.ba1_dsn(ba_dsn),.ba2_dsn(2'b11),.ba3_dsn(2'b11),
 .prog_en(1'b0),.prog_addr(22'b0),.prog_rd(1'b0),.prog_wr(1'b0),.prog_din(16'b0),.prog_dsn(2'b11),.prog_ba(2'b0),
 .prog_dst(),.prog_dok(),.prog_rdy(),.prog_ack(),.rfsh(rfsh || forced_refresh),.ack(ba_ack),.dst(ba_dst),.dok(ba_dok),.rdy(ba_rdy),.dout(ba_dout),
 .sdram_dq(dq),.sdram_a(a),.sdram_dqml(dqml),.sdram_dqmh(dqmh),.sdram_ba(bank),.sdram_nwe(nwe),.sdram_ncas(ncas),.sdram_nras(nras),.sdram_ncs(ncs),.sdram_cke(cke));
mt48lc16m16a2 ram(.Clk(memclk),.Cke(cke),.Dq(dq),.Addr(a),.Ba(bank),.Cs_n(ncs),.Ras_n(nras),.Cas_n(ncas),.We_n(nwe),.Dqm({dqmh,dqml}),.downloading(1'b0),.VS(1'b0),.frame_cnt(32'b0));
integer cycle=0, refreshes=0;
always @(posedge clk) cycle=cycle+1;
always @(posedge memclk)
 if (!init && {ncs,nras,ncas,nwe}==4'b0001) refreshes=refreshes+1;

// Latencies run from the source offer to the consumer's sampled response.
// A line bypasses the scalar outer arbiter exactly as in production.
task word_op(input bit writing, input [24:0] location, input [31:0] value,
             input [3:0] mask, input [31:0] expected, input [191:0] label);
 integer start_cycle, start_refresh;
 begin
  @(negedge clk);req=1;we=writing;addr=location;din=value;be=mask;
  start_cycle=cycle;start_refresh=refreshes;
  do @(negedge clk); while(!ack && cycle-start_cycle<3000);
  if(!ack || (!writing && dout!==expected))
   $fatal(1,"word %s address=%h got=%h expected=%h",label,location,dout,expected);
  if(label!="") $display("LATENCY kind=%0s mask=%0d first=%0d whole=%0d refreshes=%0d",
    label,mask,cycle-start_cycle,cycle-start_cycle,refreshes-start_refresh);
  req=0;repeat(8) @(negedge clk);
 end
endtask

task line_op(input [24:0] location, input [191:0] label);
 integer start_cycle, first_cycle, beats, start_refresh;
 begin
  @(negedge clk);line_addr=location;line_req=1;
  if(!line_ready)$fatal(1,"benchmark offered line while busy");
  start_cycle=cycle;start_refresh=refreshes;beats=0;first_cycle=0;
  @(negedge clk);line_req=0;
  while(beats<16 && cycle-start_cycle<3000)begin
   @(negedge clk);
   if(line_valid)begin
    if(beats==0)first_cycle=cycle;
    if(line_data !== (beats[0]?16'h9000:16'h8000)+(beats/2))
     $fatal(1,"line %s beat %0d got=%h",label,beats,line_data);
    if(line_last !== (beats==15))$fatal(1,"line last mismatch");
    beats=beats+1;
   end
  end
  if(beats!=16)$fatal(1,"benchmark line timeout");
  if(label!="")$display("LATENCY kind=%0s mask=15 first=%0d whole=%0d refreshes=%0d",
    label,first_cycle-start_cycle,cycle-start_cycle,refreshes-start_refresh);
  repeat(8) @(negedge clk);
 end
endtask

task start_refresh;
 begin
  @(negedge clk);forced_refresh=1;
  @(negedge clk);forced_refresh=0;
  wait(ctrl.u_rfsh.rfshing);
 end
endtask

integer i,j,mask_index,mixed_start;
reg [31:0] expected_mask;
initial begin
 repeat(5) @(negedge clk);rst=0;
 wait(scrub_done);@(negedge clk);phone_reset=0;
 // Initialize equal patterns in two rows in each physical bank.
 for(j=0;j<4;j=j+1)
  for(i=0;i<8;i=i+1)
   word_op(1,((j/2)*25'h800000)+((j%2)*25'h400)+i*4,
     32'h90008000+i*32'h00010001,15,0,"");
 repeat(200) @(negedge clk);
 for(j=0;j<2;j=j+1)begin
  line_op(j*25'h800000,"");
  line_op(j*25'h800000,"line_hit");
  line_op(j*25'h800000+25'h400,"line_conflict");
  start_refresh;
  line_op(j*25'h800000,"line_refresh");
  repeat(200) @(negedge clk);
 end
 for(mask_index=0;mask_index<16;mask_index=mask_index+1)begin
  word_op(1,25'h1000,0,15,0,"");
  word_op(1,25'h1000,32'h89abcdef,mask_index,0,"write_hit");
  expected_mask=((mask_index&1)?32'h000000ef:0)|((mask_index&2)?32'h0000cd00:0)|
    ((mask_index&4)?32'h00ab0000:0)|((mask_index&8)?32'h89000000:0);
  word_op(0,25'h1000,0,15,expected_mask,"");
  word_op(1,25'h1400,32'h89abcdef,mask_index,0,"write_conflict");
  word_op(1,25'h1400,0,15,0,"");
  start_refresh;
  word_op(1,25'h1400,32'h89abcdef,mask_index,0,"write_refresh");
  word_op(0,25'h1400,0,15,expected_mask,"");
  repeat(200) @(negedge clk);
 end
 // Concurrent scalar CPU and LCD offers use the actual mux/outer arbiter.
 // LCD reads the initialized bank1 line; CPU alternates rows in bank0.
 mixed_start=cycle;
 fork
  begin : cpu_load
   integer n;
   for(n=0;n<64;n=n+1)begin
    word_op(1,25'h2000+(n%2)*25'h400,n,n%16,0,"mixed_cpu_write");
    word_op(0,0,0,15,32'h90008000,"mixed_cpu_read");
   end
  end
  begin : lcd_load
   integer n,start_cycle,start_refresh;
   for(n=0;n<128;n=n+1)begin
    @(negedge clk);lcd_addr=25'h800000+(n%8)*4;lcd_req=1;start_cycle=cycle;start_refresh=refreshes;
    do @(negedge clk); while(!lcd_ack && cycle-start_cycle<3000);
    if(!lcd_ack || lcd_data!==32'h90008000+(n%8)*32'h00010001)
     $fatal(1,"mixed LCD timeout/data address=%h got=%h",lcd_addr,lcd_data);
    $display("LATENCY kind=mixed_lcd_read mask=15 first=%0d whole=%0d refreshes=%0d",
     cycle-start_cycle,cycle-start_cycle,refreshes-start_refresh);
    lcd_req=0;repeat(8) @(negedge clk);
   end
  end
  begin : mixed_refresh
   // Identical refresh request times relative to the mixed-load start. Keep
   // automatic refresh out of phase-sensitive isolated probes above.
   repeat(16)begin
    repeat(199) @(negedge clk);forced_refresh=1;
    @(negedge clk);forced_refresh=0;
   end
  end
 join
 $display("MIXED clocks=%0d cpu_words=128 lcd_words=128",cycle-mixed_start);
 if(refreshes<9)$fatal(1,"benchmark never refreshed");
 $display("PASS matched physical SDRAM latency native=%0d hz=%0d refreshes=%0d",NATIVE,SYS_CLK_HZ,refreshes);
 $finish;
end
initial begin #5000000;$fatal(1,"benchmark global timeout");end
endmodule
