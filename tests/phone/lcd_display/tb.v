`timescale 1ns/1ps
module tb;
reg clk=0,reset=1,diagnostic=1,write_valid=0,dma_valid=0;reg [2:0] save_state=0;reg [31:0] addr=0,data=0,dma_data=0;reg [14:0] dma_addr=0;
wire ce,hs,vs,hb,vb,complete,incomplete,unsupported;wire [11:0] rgb;integer i,edges=0;
always #5 clk=~clk;
ngage_lcd_display dut(.clk(clk),.reset(reset),.diagnostic(diagnostic),.status(8'h55),.save_state(save_state),.write_valid(write_valid),.write_addr(addr),.write_data(data),.dma_valid(dma_valid),.dma_frame_full(1'b0),.dma_word_addr(dma_addr),.dma_data(dma_data),.ce_pix(ce),.hsync(hs),.vsync(vs),.hblank(hb),.vblank(vb),.rgb(rgb),.frame_complete(complete),.incomplete(incomplete),.unsupported(unsupported));
task wr;input [31:0] a,d;begin @(negedge clk);write_valid=1;addr=a;data=d;@(negedge clk);write_valid=0;end endtask
initial begin
 repeat(3)@(negedge clk);reset=0;
 repeat(48)begin @(negedge clk);if(ce)edges=edges+1;end
 if(edges!=3 || rgb!==12'hf00)begin $display("FAIL diagnostic raster ce=%0d rgb=%h",edges,rgb);$finish;end
 @(negedge clk);dut.scan_x=128;dut.scan_y=210;
 save_state=0;#1;if(rgb!==12'h333)begin $display("FAIL unmounted color");$finish;end
 save_state=1;#1;if(rgb!==12'hf90)begin $display("FAIL dirty color");$finish;end
 save_state=2;#1;if(rgb!==12'h0cf)begin $display("FAIL saving color");$finish;end
 save_state=3;#1;if(rgb!==12'h0f0)begin $display("FAIL saved color");$finish;end
 save_state=4;#1;if(rgb!==12'hf00)begin $display("FAIL error color");$finish;end
 diagnostic=0;wr('h0c121200,'h09200000);wr('h0c121208,'h5c);wr('h0c121200,'h8924d67f);
 for(i=0;i<18303;i=i+1)wr('h0c121208,i==0 ? 32'h0abc0123 : i);
 if(complete || !incomplete)begin $display("FAIL premature completion");$finish;end
 wr('h0c121208,32'h0abc0123);
 if(!complete || incomplete || dut.framebuffer.memory[18303]!==24'habc123)begin $display("FAIL complete frame");$finish;end
 wr('h0c121200,'h09200000);wr('h0c121208,'haf);
 wr('h0c121208,'hfe);if(!unsupported || !complete)begin $display("FAIL unsupported command diagnostic");$finish;end
 if(!dut.display_on)begin $display("FAIL display on");$finish;end
 @(negedge clk);dut.x=72;dut.y=16;dut.div=0;@(negedge clk);#1;
 if(rgb!==12'h123)begin $display("FAIL first pixel orientation %h",rgb);$finish;end
 repeat(16)@(negedge clk);#1;if(rgb!==12'habc)begin $display("FAIL second pixel orientation %h",rgb);$finish;end
 @(negedge clk);dut.x=336;dut.div=0;@(negedge clk);#1;if(hs!==0)begin $display("FAIL horizontal sync assertion");$finish;end
 @(negedge clk);dut.x=368;dut.div=0;@(negedge clk);#1;if(hs!==1)begin $display("FAIL horizontal sync release");$finish;end
 @(negedge clk);dma_valid=1;dma_addr=7;dma_data=32'h01110222;@(negedge clk);dma_valid=0;
 if(dut.framebuffer.memory[7]!==24'h111222)begin $display("FAIL DMA update");$finish;end
 $display("PASS diagnostic raster and direct LCD frame completeness");$finish;
end
endmodule
