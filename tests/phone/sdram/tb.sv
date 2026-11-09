`timescale 1ns/1ps
module tb;
parameter INVERTED_CLOCK=0, CAPTURE_NEGEDGE=0;
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
wire mreq,mwe,mack; wire [24:0] maddr; wire [31:0] mdata,mrdata; wire [3:0] mbe;
reg dma_req=0, dma_we=0, cpu_lock=0; reg [24:0] dma_addr=0; reg [31:0] dma_data=0; reg [3:0] dma_be=0; wire dma_ack; wire [31:0] dma_rdata;
ngage_sdram_arbiter arb(clk,phone_reset,cpu_lock,req,we,addr,din,be,ack,dout,
 dma_req,dma_we,dma_addr,dma_data,dma_be,dma_ack,dma_rdata,mreq,mwe,maddr,mdata,mbe,mack,mrdata);
ngage_sdram_adapter #(.RAM_BYTES(32),.REFRESH_PERIOD(250)) adapter(clk,rst,phone_reset,init,mreq,mwe,maddr,mdata,mbe,mack,mrdata,scrub_done,ba_addr,ba_din,ba_dsn,rd,wr,ba_ack,ba_rdy,ba_dout,rfsh);
jtframe_sdram64 #(.AW(22),.HF(1),.READ_CAPTURE_NEGEDGE(CAPTURE_NEGEDGE),.BA0_LEN(16),.BA1_LEN(16),.BA2_LEN(16),.BA3_LEN(16),.PROG_LEN(16),.BA0_WEN(1),.BA1_WEN(1)) ctrl(
 .rst(rst),.clk(clk),.init(init),.ba0_addr(ba_addr),.ba1_addr(ba_addr),.ba2_addr(22'b0),.ba3_addr(22'b0),
 .rd(rd),.wr(wr),.ba0_din(ba_din),.ba1_din(ba_din),.ba2_din(16'b0),.ba3_din(16'b0),
 .ba0_dsn(ba_dsn),.ba1_dsn(ba_dsn),.ba2_dsn(2'b11),.ba3_dsn(2'b11),
 .prog_en(1'b0),.prog_addr(22'b0),.prog_rd(1'b0),.prog_wr(1'b0),.prog_din(16'b0),.prog_dsn(2'b11),.prog_ba(2'b0),
 .prog_dst(),.prog_dok(),.prog_rdy(),.prog_ack(),.rfsh(rfsh),.ack(ba_ack),.dst(ba_dst),.dok(ba_dok),.rdy(ba_rdy),.dout(ba_dout),
 .sdram_dq(dq),.sdram_a(a),.sdram_dqml(dqml),.sdram_dqmh(dqmh),.sdram_ba(bank),.sdram_nwe(nwe),.sdram_ncas(ncas),.sdram_nras(nras),.sdram_ncs(ncs),.sdram_cke(cke));
mt48lc16m16a2 ram(.Clk(memclk),.Cke(cke),.Dq(dq),.Addr(a),.Ba(bank),.Cs_n(ncs),.Ras_n(nras),.Cas_n(ncas),.We_n(nwe),.Dqm({dqmh,dqml}),.downloading(1'b0),.VS(1'b0),.frame_cnt(32'b0));
integer acknowledgments=0, refreshes=0, count=0, i, before_ack;
always @(posedge clk) begin
 if(ack) acknowledgments<=acknowledgments+1;
 if(!init && {ncs,nras,ncas,nwe}==4'b0001) refreshes<=refreshes+1;
 if(acknowledgments==0 && ba_ack[0] && rd[0]) $display("TIMING ack=%0t",$time);
 if(acknowledgments==0 && ba_rdy[0] && !we && req) $display("TIMING rdy=%0t data=%h",$time,ba_dout);
end
task transfer(input bit w,input [24:0] address,input [31:0] value,input [3:0] mask,input [31:0] expected);
 begin
 @(negedge clk);before_ack=acknowledgments;we=w;addr=address;din=value;be=mask;req=1;
 count=0; while(!ack && count<3000) begin @(negedge clk);count=count+1; end
 if(!ack) $fatal(1,"timeout address %h",address);
 if(!w && dout!==expected) $fatal(1,"read %h got %h expected %h",address,dout,expected);
 req=0;
 repeat(5) @(negedge clk);
 if(ack || acknowledgments != before_ack+1) $fatal(1,"duplicate or missing acknowledgement");
 req=0;repeat(3) @(negedge clk);
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
 if(!dma_ack) $fatal(1,"DMA starved");
 dma_req=0;repeat(5) @(negedge clk);transfer(0,20,0,15,32'h55aa55aa);
 // Keep the memory busy across many refresh intervals.
 for(i=0;i<80;i=i+1) begin transfer(1,8,i,15,0);transfer(0,8,0,15,i);end
 repeat(1500) @(negedge clk); if(refreshes<9) $fatal(1,"refresh not operating %d",refreshes);
 $display("PASS SDRAM real controller and model, refreshes=%0d",refreshes);$finish;
end
initial begin #5000000; $fatal(1,"global timeout");end
endmodule
