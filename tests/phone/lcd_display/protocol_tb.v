`timescale 1ns/1ps
module tb;
`include "tests/phone/lcd_display/fixture_count.vh"
reg clk=0,reset=1,write_valid=0,dma_valid=0;reg [31:0] addr=0,data=0,dma_data=0;reg [14:0] dma_addr=0;
wire unsupported,uv;wire [31:0] ud,uh;wire [7:0] uc;
reg [63:0] fixture[0:FIXTURE_WRITES-1];integer i,unknown_count=0;
always #5 clk=~clk;
ngage_lcd_display dut(.clk(clk),.reset(reset),.diagnostic(1'b0),.status(8'b0),.save_state(3'b0),.write_valid(write_valid),.write_addr(addr),.write_data(data),.dma_valid(dma_valid),.dma_frame_full(1'b0),.dma_word_addr(dma_addr),.dma_data(dma_data),.unsupported(unsupported),.unsupported_valid(uv),.unsupported_data(ud),.unsupported_header(uh),.unsupported_command(uc));
always @(negedge clk)if(uv)unknown_count=unknown_count+1;
task wr;input [31:0] a,d;begin @(negedge clk);addr=a;data=d;write_valid=1;@(negedge clk);write_valid=0;end endtask
task cmd;input [7:0] c;begin wr('h0c121200,'h09200000);wr('h0c121208,c);end endtask
task win;input [7:0] c;input [31:0] packed_value;begin cmd(c);wr('h0c121200,'h09240003);wr('h0c121208,packed_value);wr('h0c121208,0);end endtask
task rst;begin @(negedge clk);reset=1;@(negedge clk);reset=0;end endtask
initial begin
 $readmemh("tests/phone/lcd_display/startup_commands.hex",fixture);
 rst();
 for(i=0;i<FIXTURE_WRITES;i=i+1)wr(fixture[i][63:32],fixture[i][31:0]);
 if(dut.row_start!=0 || dut.row_end!=208 || dut.col_start!=2 || dut.col_end!=177 || !dut.memory_write)$fatal(1,"fresh cold-boot window fixture");
 if(!unsupported || unknown_count==0)$fatal(1,"unknown init commands hidden");
 rst();win('h15,'h0b100002);win('h75,'h0d000000);
 if(unsupported || dut.window_words!=0)$fatal(1,"stock full-window framing");
 // Hybrid host uses 207; accepting the full panel does not settle clipping.
 win('h75,'h0cf00000);if(unsupported)$fatal(1,"reference full window");
 cmd('h5c);wr('h0c121200,'h8924d67f);
 @(negedge clk);write_valid=1;addr='h0c121208;data=32'h0abc0123;dma_valid=1;dma_addr=0;dma_data='h04560678;
 @(negedge clk);write_valid=0;dma_valid=0;
 if(dut.framebuffer.memory[0]!==24'habc123)$fatal(1,"CPU/DMA direct priority");
 rst();win('h75,'h00a00003);
 if(!unsupported || uc!='h75 || uh!='h09240003 || ud!='h00a00003 || dut.row_start!=3 || dut.row_end!=10)$fatal(1,"partial-window context");
 cmd('h5c);wr('h0c121200,'h8924d67f);wr('h0c121208,0);
 if(dut.memory_write || dut.framebuffer.memory[0]!==24'habc123)$fatal(1,"partial geometry silently rendered");
 rst();win('h15,'h0b100003);if(!unsupported || dut.col_start!=3)$fatal(1,"odd window start hidden");
 rst();cmd('h75);wr('h0c121200,'h09240003);wr('h0c121208,'h0d000000);wr('h0c121208,1);
 if(!unsupported || uc!='h75 || uh!='h09240003)$fatal(1,"nonzero trailing word ignored");
 rst();cmd('h75);wr('h0c121200,'h09240003);wr('h0c121208,'h0d000000);wr('h0c121200,'h09200000);
 if(!unsupported || uh!='h09240003)$fatal(1,"interrupted window payload hidden");
 rst();cmd('hca);wr('h0c121200,'h0924000a);wr('h0c121208,'hf640f208);
 if(!unsupported || uc!='hca || uh!='h0924000a || ud!='hf640f208)$fatal(1,"init parameter diagnostic context");
 rst();cmd('hfe);if(!unsupported || uc!='hfe || uh!='h09200000)$fatal(1,"unknown command context");
 $display("PASS LCD cold-boot fixture, window framing, unknown context and safe partial-window rejection");$finish;
end
endmodule
