`timescale 1ns/1ps
module tb;
reg clk=0,reset=1,valid=0,full=0,write_valid=0;reg [14:0] addr=0;reg [31:0] data=0,write_addr=0,write_data=0;wire complete,incomplete;wire [11:0] rgb;integer row,w;
always #5 clk=~clk;
ngage_lcd_display dut(.clk(clk),.reset(reset),.diagnostic(1'b0),.status(8'b0),.save_state(3'd0),.write_valid(write_valid),.write_addr(write_addr),.write_data(write_data),
 .dma_valid(valid),.dma_frame_full(full),.dma_word_addr(addr),.dma_data(data),.ce_pix(),.hsync(),.vsync(),.hblank(),.vblank(),.rgb(rgb),.frame_complete(complete),.incomplete(incomplete));
task wr;input [31:0] a,d;begin @(negedge clk);write_valid=1;write_addr=a;write_data=d;@(negedge clk);write_valid=0;end endtask
initial begin
 repeat(2)@(negedge clk);reset=0;
 wr('h0c121200,'h09200000);wr('h0c121208,'haf);
 // A partial transfer becomes visible without a full-frame coverage gate.
 for(w=0;w<20;w=w+1)begin addr=w;data='h0abc0123;valid=1;@(negedge clk);end
 valid=0;#1;if(!incomplete || complete)$fatal(1,"partial transfer status");
 dut.x=72;dut.y=16;dut.div=0;repeat(3)@(negedge clk);#1;
 if(rgb!==12'h123)$fatal(1,"partial pixel hidden %h",rgb);
 // Untouched pixels retain deterministic initial black.
 dut.x=72;dut.y=17;dut.div=0;repeat(3)@(negedge clk);#1;
 if(rgb!==0)$fatal(1,"unwritten pixel not black %h",rgb);
 // Populate all complete rows in reverse order, as separate DMA bands.
 for(row=207;row>=0;row=row-1)begin
  for(w=0;w<88;w=w+1)begin addr=row*88+w;data=((32'h100+row)<<16)|(32'h200+w);valid=1;@(negedge clk);end
  valid=0;@(negedge clk);
  if(complete)$fatal(1,"invented full-transfer event");
 end
 if(dut.framebuffer.memory[0]!==24'h100200 || dut.framebuffer.memory[18216]!==24'h1cf200)$fatal(1,"band pixel addressing");
 full=1;@(negedge clk);full=0;
 if(!complete || incomplete)$fatal(1,"explicit full-transfer status");
 $display("PASS partial and out-of-order LCD pixel updates without coverage gating");$finish;
end
endmodule
