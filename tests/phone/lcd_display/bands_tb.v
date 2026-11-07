`timescale 1ns/1ps
module tb;
reg clk=0,reset=1,valid=0;reg [14:0] addr=0;reg [31:0] data=0;wire complete,incomplete;integer row,w;
always #5 clk=~clk;
ngage_lcd_display dut(.clk(clk),.reset(reset),.diagnostic(1'b0),.status(8'b0),.save_state(3'd0),.write_valid(1'b0),.write_addr(32'b0),.write_data(32'b0),
 .dma_valid(valid),.dma_frame_full(1'b0),.dma_word_addr(addr),.dma_data(data),.ce_pix(),.hsync(),.vsync(),.hblank(),.vblank(),.rgb(),.frame_complete(complete),.incomplete(incomplete));
initial begin
 repeat(2)@(negedge clk);reset=0;
 // A short partial line must not mark that line complete.
 for(w=0;w<20;w=w+1)begin addr=w;valid=1;@(negedge clk);end
 valid=0;#1;if(dut.valid_rows[0] || !incomplete || complete)begin $display("FAIL partial line validity");$finish;end
 // Populate all complete rows in reverse order, as separate DMA bands.
 for(row=207;row>=0;row=row-1)begin
  for(w=0;w<88;w=w+1)begin addr=row*88+w;data={16'h0100+row,16'h0200+w};valid=1;@(negedge clk);end
  valid=0;@(negedge clk);
  if(row>0 && complete)begin $display("FAIL premature coverage");$finish;end
 end
 if(!complete || incomplete || !(&dut.valid_rows))begin $display("FAIL complete line-band coverage");$finish;end
 $display("PASS partial and out-of-order LCD line-band validity");$finish;
end
endmodule
