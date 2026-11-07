`timescale 1ns/1ps
module tb;
reg clk=0,reset=1,request=0,mounted=0,busy=0,error=0,wr=0;reg [26:0] addr=0;reg [15:0] data=0;
wire download,blocked,wait_req,valid,failed,mv;wire [31:0] ma,md;wire [3:0] be;
always #5 clk=~clk;
ngage_bundle_gate gate(.clk(clk),.reset(reset),.request(request),.save_mounted(mounted),.save_busy(busy),.save_error(error),.download(download),.blocked(blocked));
ngage_loader #(.CORE_LEN(4),.EXT_LEN(4),.C_LEN(4),.PMM_LEN(4)) loader(.clk(clk),.reset(reset),.download(download),.wr(wr),.addr(addr),.data(data),.wait_req(wait_req),.valid(valid),.failed(failed),.mem_valid(mv),.mem_ready(1'b1),.mem_addr(ma),.mem_data(md),.mem_be(be),.mem_done(1'b1));
initial begin
 repeat(2)@(negedge clk);reset=0;loader.valid=1;mounted=1;request=1;wr=1;
 repeat(4)@(negedge clk);if(download || !blocked || !valid || mv)begin $display("FAIL mounted save overwritten");$finish;end
 request=0;mounted=0;busy=1;@(negedge clk);request=1;repeat(2)@(negedge clk);if(download||!blocked||!valid||mv)begin $display("FAIL busy save overwritten");$finish;end
 request=0;busy=0;error=1;@(negedge clk);request=1;repeat(2)@(negedge clk);if(download||!blocked||!valid||mv)begin $display("FAIL failed save overwritten");$finish;end
 request=0;error=0;@(negedge clk);request=1;wr=0;repeat(2)@(negedge clk);if(!download||blocked||valid)begin $display("FAIL safe reload not started");$finish;end
 $display("PASS mounted, busy and failed save protect bundle-owned DDR");$finish;
end
endmodule
