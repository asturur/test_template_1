`timescale 1ns/1ps
module tb;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    reg rv = 0, rl = 0, tr = 0;
    reg [7:0] rd = 0;
    wire rr, tv, tl, unsupported;
    wire [7:0] td;
    reg [7:0] request[0:11], expected[0:15];
    integer i, n, unsupported_count = 0, cycles = 0;
    ngage_upp_dsp_peer dut(clk,reset,rv,rr,rd,rl,tv,tr,td,tl,unsupported);
    always @(posedge clk) begin
        cycles <= cycles + 1;
        if (unsupported) unsupported_count <= unsupported_count + 1;
        if (cycles > 10000) $fatal(1,"peer timeout");
    end
    task send;
        begin
            for (i = 0; i < 12; i = i + 1) begin
                @(negedge clk);
                if (!rr) $fatal(1,"request unexpectedly blocked");
                rv = 1; rd = request[i]; rl = i == 11;
            end
            @(negedge clk); rv = 0; rl = 0;
        end
    endtask
    task receive;
        input integer count;
        reg [7:0] held;
        begin
            for (n = 0; n < count; n = n + 1) begin
                if (!tv || td !== expected[n] || tl !== (n == count-1))
                    $fatal(1,"reply byte%0d valid%b got%h expected%h last%b",n,tv,td,expected[n],tl);
                held = td;
                repeat (3) begin
                    @(negedge clk);
                    if (!tv || td !== held || rr) $fatal(1,"stalled response changed");
                end
                tr = 1;
                @(negedge clk); tr = 0;
            end
            if (tv || !rr) $fatal(1,"reply did not retire");
        end
    endtask
    initial begin
        request[0]='h12; request[1]='h7c; request[2]=0; request[3]='hf1;
        request[4]=0; request[5]=6; request[6]='h01; request[7]='h24;
        request[8]='h20; request[9]='ha0; request[10]=2; request[11]='h55;
        expected[0]='h12;expected[1]=0;expected[2]='h7c;expected[3]='hf1;
        expected[4]=0;expected[5]=6;expected[6]='h24;expected[7]='h01;
        expected[8]='h20;expected[9]='ha1;expected[10]=1;expected[11]=3;
        repeat(3) @(negedge clk); reset = 0;
        // Exact native RF packet includes uninitialized padding55; it is not data.
        send(); receive(12);
        // Also cover device-address low bits and a different object pair.
        request[1]='h7e;request[2]=1;request[6]='h42;request[7]='h1b;
        expected[1]=1;expected[2]='h7e;expected[6]='h1b;expected[7]='h42;
        request[8]='h40;request[10]=1;
        expected[5]=10;expected[8]='h40;expected[10]=5;
        expected[11]='h48;expected[12]='h44;expected[13]='h4c;
        expected[14]='h30;expected[15]='h31;
        send(); receive(16);
        // Preserve the original media00 fixture profile as well.
        request[0]=0;expected[0]=0;
        send(); receive(16);
        request[0]='h12;expected[0]='h12;
        // Media12 is not permission to answer other media/resources/lengths.
        request[0]='h13;send();repeat(3)@(negedge clk);
        if(tv||unsupported_count!=1)$fatal(1,"unsupported media policy");
        request[0]='h12;request[3]='hf2;send();repeat(3)@(negedge clk);
        if(tv||unsupported_count!=2)$fatal(1,"unsupported resource policy");
        request[3]='hf1;request[5]=5;send();repeat(3)@(negedge clk);
        if(tv||unsupported_count!=3)$fatal(1,"malformed length policy");
        request[5]=6;
        // Unknown subtype gets no invented success reply.
        request[10]=9; send(); repeat(3) @(negedge clk);
        if (tv || unsupported_count != 4) $fatal(1,"unsupported policy");
        request[10]=1; send();
        reset = 1; @(negedge clk); reset = 0;
        if (tv || !rr) $fatal(1,"reset did not discard pending reply");
        $display("PASS UPP DSP peer RF/SW version framing, object/device routing, backpressure, unknown request and reset");
        $finish;
    end
endmodule
