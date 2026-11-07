`timescale 1ns/1ps
module tb;
reg clk=0,reset=1,req=0,commit=0,we=0;reg [31:0] addr=0,din=0;reg [3:0] sel=15;
wire claim,bad,mreq,valid,irq;wire [31:0] dout,ldata;wire [24:0] ma;wire [14:0] la;
reg ack=0,clear=0;reg [31:0] md=0;integer n=0;always #5 clk=~clk;
ngage_lcd_dma dut(.clk(clk),.reset(reset),.req(req),.commit(commit),.we(we),.addr(addr),.din(din),.sel(sel),.claim(claim),.bad(bad),.dout(dout),.mem_req(mreq),.mem_addr(ma),.mem_ack(ack),.mem_data(md),.lcd_valid(valid),.lcd_word_addr(la),.lcd_data(ldata),.irq_pending(irq),.irq_clear(clear));
task wr;input [31:0] a,d;input fail;begin @(negedge clk);addr=a;din=d;req=1;we=1;#1;if(!claim || bad!==fail)begin $display("FAIL control %h bad %b",a,bad);$finish;end commit=!fail;@(negedge clk);req=0;commit=0;end endtask
task beat;input [24:0] a;input [31:0] d;input [14:0] index;begin
 wait(mreq);repeat(3)@(negedge clk);if(ma!==a || irq)begin $display("FAIL DMA stall/address %h",ma);$finish;end
 md=d;ack=1;@(negedge clk);ack=0;#1;if(!valid || la!==index || ldata!==d)begin $display("FAIL LCD write");$finish;end
end endtask
initial begin
 repeat(2)@(negedge clk);reset=0;
 wr('h0c120348,2,1);
 wr('h0c120354,'h0a000024,0);wr('h0c120360,'h10121208,0);wr('h0c12036c,1,0);wr('h0c120348,2,0);
 wr('h0c120348,2,1);beat('h24,'h12345678,1);beat('h28,'habcdef01,2);
 @(negedge clk);if(!irq || mreq)begin $display("FAIL completion IRQ");$finish;end
 @(negedge clk);clear=1;@(negedge clk);clear=0;if(irq)begin $display("FAIL IRQ clear");$finish;end
 wr('h0c120360,'h123,0);wr('h0c120348,2,1);
 $display("PASS LCD DMA destination, stalls, data and completion IRQ");$finish;
end
endmodule
