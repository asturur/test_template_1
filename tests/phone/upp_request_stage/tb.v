`timescale 1ns/1ps
module tb;
    reg clk=0, reset=1, cyc=0, stb=0, we=0, code=0;
    reg [31:0] address=0, data=0;
    reg [3:0] sel=0;
    wire oc, os, ow, oi;
    wire [31:0] oa, od;
    wire [3:0] ob;
    integer n;
    ngage_upp_request_stage dut (
        .clk(clk),.reset(reset),.in_cyc(cyc),.in_stb(stb),.in_we(we),.in_code(code),
        .in_address(address),.in_data(data),.in_sel(sel),
        .out_cyc(oc),.out_stb(os),.out_we(ow),.out_code(oi),.out_address(oa),.out_data(od),.out_sel(ob)
    );
    task tick; begin #2;clk=1;#2;clk=0;#2;end endtask
    initial begin
        tick;reset=0;cyc=1;stb=1;we=1;code=0;address=32'h0c120308;data=2;sel=15;#1;
        if(oc || os)$fatal(1,"packet reached decode before capture");
        tick;
        if(!oc || !os || {ow,oi,oa,od,ob} !== {1'b1,1'b0,32'h0c120308,32'd2,4'hf})$fatal(1,"packet capture");
        // Downstream waits; subsequent upstream changes cannot borrow payload.
        we=0;code=1;address=32'hffffffff;data=32'h12345678;sel=3;
        for(n=0;n<5;n=n+1)begin tick;if({ow,oi,oa,od,ob} !== {1'b1,1'b0,32'h0c120308,32'd2,4'hf})$fatal(1,"held packet changed");end
        cyc=0;#1;if(oc || os)$fatal(1,"CYC cancellation was delayed");tick;
        cyc=1;stb=1;#1;if(oc)$fatal(1,"canceled packet replay");tick;
        if({ow,oi,oa,od,ob} !== {1'b0,1'b1,32'hffffffff,32'h12345678,4'h3})$fatal(1,"next packet identity");
        stb=0;#1;if(os)$fatal(1,"STB withdrawal delayed");tick;
        stb=1;#1;if(oc)$fatal(1,"withdrawn packet replay");tick;
        reset=1;#1;if(oc || os)$fatal(1,"reset suppression delayed");tick;cyc=0;stb=0;reset=0;tick;
        if(oc || os)$fatal(1,"reset replay");
        $display("PASS UPP request stage: sample latency, held payload, CYC/STB cancellation, next owner and reset");$finish;
    end
endmodule
