`timescale 1ns/1ps
module tb;
reg clk=0,reset=1,req=0,commit=0,we=0;reg [31:0] addr=0,din=0;wire claim,bad;wire [31:0] dout;
wire dreq,dack,valid,irq,full;wire [24:0] da;wire [31:0] dr,ld;wire [14:0] la;
reg cr=0,lock=0;wire ca;wire [31:0] cd;wire mr,mw;wire [24:0] ma;wire [31:0] mwdata;wire [3:0] mbe;reg mack=0;reg [31:0] mdata=0;
wire frame_complete,incomplete;
`ifdef RETAINED_FRAME
reg [31:0] reference[0:18303];
initial $readmemh("build/sim/unit-lcd-dma/firmware-frame.hex",reference);
`endif
function [23:0] pixel_bits;
 input [31:0] word_value;
 begin pixel_bits={word_value[27:16],word_value[11:0]};end
endfunction
reg [31:0] pixel_checksum=0;
integer writes=0,cpu_done=0,idx;reg [31:0] frame_sum;reg saw_full=0;reg [31:0] checksum=0;always #5 clk=~clk;
ngage_lcd_dma dma(.clk(clk),.reset(reset),.req(req),.commit(commit),.we(we),.addr(addr),.din(din),.sel(4'hf),.claim(claim),.bad(bad),.dout(dout),.mem_req(dreq),.mem_addr(da),.mem_ack(dack),.mem_data(dr),.lcd_valid(valid),.lcd_frame_full(full),.lcd_word_addr(la),.lcd_data(ld),.irq_pending(irq),.irq_clear(1'b0));
ngage_sdram_arbiter arb(.clk(clk),.reset(reset),.cpu_lock(lock),.cpu_req(cr),.cpu_we(1'b0),.cpu_addr(25'h10),.cpu_data(32'b0),.cpu_be(4'hf),.cpu_ack(ca),.cpu_rdata(cd),.dma_req(dreq),.dma_we(1'b0),.dma_addr(da),.dma_data(32'b0),.dma_be(4'hf),.dma_ack(dack),.dma_rdata(dr),.mem_req(mr),.mem_we(mw),.mem_addr(ma),.mem_data(mwdata),.mem_be(mbe),.mem_ack(mack),.mem_rdata(mdata));
ngage_lcd_display display(.clk(clk),.reset(reset),.diagnostic(1'b0),.status(8'b0),.save_state(3'd0),.write_valid(1'b0),.write_addr(32'b0),.write_data(32'b0),
 .dma_valid(valid),.dma_frame_full(full),.dma_word_addr(la),.dma_data(ld),.ce_pix(),.hsync(),.vsync(),.hblank(),.vblank(),.rgb(),.frame_complete(frame_complete),.incomplete(incomplete));
always @(negedge clk)begin
 mack=mr;
`ifdef RETAINED_FRAME
 if(ma>=25'h20 && ma<25'h11e20)mdata=reference[(ma-25'h20)>>2];else mdata=0;
`else
 mdata={7'b0,ma};
`endif
end
always @(posedge clk)begin if(ca)cpu_done<=cpu_done+1;if(full)saw_full<=1;if(valid)begin if(la!==writes ||
`ifdef RETAINED_FRAME
 ld!==reference[writes]
`else
 ld!==32'h20+writes*4
`endif
 )begin $display("FAIL DMA word %0d %h %h",writes,la,ld);$finish;end writes<=writes+1;checksum<=checksum+ld;pixel_checksum<=pixel_checksum+pixel_bits(ld);end end
task wr;input [31:0] a,d;begin @(negedge clk);addr=a;din=d;req=1;we=1;commit=1;#1;if(bad || !claim)begin $display("FAIL DMA setup");$finish;end @(negedge clk);req=0;commit=0;end endtask
initial begin
 repeat(2)@(negedge clk);reset=0;
 wr('h0c120354,'h0a000020);wr('h0c120360,'h0c121208);wr('h0c12036c,18303);
 lock=1;cr=1;wr('h0c120348,2);repeat(20)@(negedge clk);if(writes!=0 || cpu_done==0)begin $display("FAIL SWP lock");$finish;end
 cr=0;lock=0;wait(irq);@(negedge clk);
 if(writes!=18304 || !saw_full || !frame_complete || incomplete ||
`ifdef RETAINED_FRAME
 checksum!==32'h6de5f326 || display.framebuffer.memory[0]!==pixel_bits(reference[0]) || display.framebuffer.memory[18303]!==pixel_bits(reference[18303])
`else
 display.framebuffer.memory[0]!==pixel_bits(32'h20) || display.framebuffer.memory[18303]!==pixel_bits(32'h11e1c)
`endif
 )begin $display("FAIL frame/IRQ writes=%0d full=%b",writes,full);$finish;end
 frame_sum=0;
 for(idx=0;idx<18304;idx=idx+1)begin
`ifdef RETAINED_FRAME
  if(display.framebuffer.memory[idx]!==pixel_bits(reference[idx]))begin $display("FAIL framebuffer word %0d",idx);$finish;end
`else
  if(display.framebuffer.memory[idx]!==pixel_bits(32'h20+idx*4))begin $display("FAIL framebuffer word %0d",idx);$finish;end
`endif
  frame_sum=frame_sum+display.framebuffer.memory[idx];
 end
 if(frame_sum!==pixel_checksum)begin $display("FAIL framebuffer checksum");$finish;end
 $display("PASS LCD full DMA through SDRAM arbiter words=%0d checksum=%h",writes,frame_sum);$finish;
end
initial begin #5000000;$display("FAIL timeout");$finish;end
endmodule
