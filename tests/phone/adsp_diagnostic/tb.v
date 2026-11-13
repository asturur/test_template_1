`timescale 1ns/1ps
module tb;
    reg clk=0,reset=1,req=0,rr=0,locked=1,fv=1,allow=1,inject=0;
    reg probe=0;
    reg [6:0] probe_addr=7'h1a;
    reg [15:0] probe_word=16'h1e00;
    reg [15:0] tid=16'h42,marker=16'hfffc;
    wire ready,cv,cr,done,unsupported,reply,err,seen;
    wire [6:0] ca;
    wire [15:0] cw,result;
    integer count=0,i;
    real half_period=6.410256;
    initial if($value$plusargs("half_period=%f",half_period))begin end
    always #(half_period) clk=~clk;
    ngage_adsp_diagnostic dut(clk,reset,req,ready,tid,locked,fv,marker,
        cv,cr && allow,ca,cw,reply,err|inject,done,rr,unsupported,result);
    ngage_aic23 codec(clk,reset,probe || (cv&&allow),probe ? probe_addr : ca,probe ? probe_word : cw,cr,reply,err,seen);
    // Both sides see the same admission gate; valid must remain held on stall.
    always @(posedge clk) if(!reset && cv && cr && allow) count<=count+1;
    task run;
        input l,v,e;
        input [15:0] m,id,expected;
        input uns;
        integer before_count;
        begin
            before_count=count;
            @(negedge clk);locked=l;fv=v;inject=e;marker=m;tid=id;req=1;allow=0;
            if(!ready)$fatal(1,"not ready");
            @(negedge clk);req=0;
            if(id==16'h42)begin
                repeat(5)begin
                    @(negedge clk);
                    if(!cv || done || ca!=7'h1a || cw!=16'h1e00)$fatal(1,"codec request/stall");
                end
                allow=1;
            end
            wait(done);@(negedge clk);
            if(result!==expected || unsupported!==uns)$fatal(1,"result %h uns%b",result,unsupported);
            if(count-before_count!=(uns?0:1))$fatal(1,"codec transfer count");
            repeat(4)begin
                @(negedge clk);
                if(!done || result!==expected || ready || cv)$fatal(1,"response ownership");
            end
            rr=1;@(negedge clk);rr=0;
            if(!ready || done)$fatal(1,"response release");
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);reset=0;
        // Address and control data failures are actual codec NACK responses.
        @(negedge clk);probe=1;probe_addr=7'h1b;
        @(negedge clk);probe=0;
        if(!reply || !err || seen)$fatal(1,"wrong codec address accepted");
        @(negedge clk);probe=1;probe_addr=7'h1a;probe_word=16'h1e01;
        @(negedge clk);probe=0;
        if(!reply || !err || seen)$fatal(1,"wrong codec reset accepted");
        @(negedge clk);
        run(1,1,0,16'hfffc,16'h42,0,0);
        if(!seen)$fatal(1,"codec reset missing");
        run(0,1,0,16'hfffc,16'h42,12,0);
        run(1,0,0,16'hfffc,16'h42,12,0);
        run(1,1,0,16'hffff,16'h42,12,0);
        run(1,1,1,16'hfffc,16'h42,12,0);
        run(1,1,0,16'hfffc,16'h43,12,1);
        // Reset a held request: no stale response or codec operation survives.
        @(negedge clk);allow=0;req=1;
        @(negedge clk);req=0;reset=1;
        @(negedge clk);reset=0;#1;
        if(done || cv || seen || !ready)$fatal(1,"reset ownership");
        $display("PASS D550 diagnostic42: clock/flash/codec failures, exact codec reset, stalls, response ownership, unknown test and reset");
        $finish;
    end
    initial begin #100000; $fatal(1,"timeout");end
endmodule
