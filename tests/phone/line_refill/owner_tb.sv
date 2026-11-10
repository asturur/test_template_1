`timescale 1ns/1ps
module tb;
reg clk=0,reset=1,blocked=1;always #5 clk=~clk;
reg cr=0,dr=0,ready=0,reject=0,valid=0,wide=0,last=0,error=0;
reg [63:0] data=0;wire req,cready,dready,cv,dv,crej,drej,ow,ol,oe;wire [31:0] addr;wire [63:0] od;
arm920_line_owner #(.ENABLE(1)) dut(.clk(clk),.reset(reset),.blocked(blocked),
 .c_req(cr),.c_addr(32'h00300020),.c_ready(cready),.c_valid(cv),.c_reject(crej),
 .d_req(dr),.d_addr(32'h0a000040),.d_ready(dready),.d_valid(dv),.d_reject(drej),
 .out_data(od),.out_wide(ow),.out_last(ol),.out_error(oe),.line_req(req),.line_addr(addr),
 .line_ready(ready),.line_reject(reject),.line_valid(valid),.line_data(data),.line_wide(wide),.line_last(last),.line_error(error));
task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
initial begin
 tick();reset=0;cr=1;dr=1;tick();if(req)$fatal(1,"passed blocked bus");blocked=0;
 tick();if(!req || addr!==32'h0a000040)$fatal(1,"wrong first owner");
 tick();if(addr!==32'h0a000040)$fatal(1,"unaccepted descriptor changed");
 blocked=1;ready=1;#1;if(req || cready || dready)$fatal(1,"accepted behind newly buffered write");
 tick();blocked=0;#1;if(!req)$fatal(1,"lost deferred line");ready=1;
 #1;if(cready || !dready)$fatal(1,"wrong acceptance");tick();dr=0;ready=0;
 valid=1;data=64'h12345678;wide=1;last=1;tick();valid=0;last=0;
 if(!dv || cv || od!==64'h12345678 || !ow || !ol)$fatal(1,"lost last beat after owner release");
 tick();if(!req || addr!==32'h00300020)$fatal(1,"waiting code requester starved");
 ready=1;tick();cr=0;ready=0;reject=1;tick();reject=0;
 if(!crej || drej)$fatal(1,"rejection lost");
 tick();cr=1;tick();ready=1;tick();cr=0;ready=0;
 reset=1;tick();reset=0;valid=1;last=1;error=1;tick();
 if(cv || dv || req)$fatal(1,"stale reset response");
 $display("PASS registered line owner: arbitration, blocked admission, held offer, last/reject, reset");$finish;
end
initial begin #10000;$fatal(1,"timeout");end
endmodule
