`timescale 1ns/1ps
module test;
    reg clk=0, reset=1, lookup=0, fill=0, inv=0, by_mva=0, lock_write=0;
    reg [31:0] va=0, fill_va=0, inv_va=0, lock_data=0;
    reg [37:0] fill_data=0;
    wire valid, hit;
    wire [37:0] data;
    wire [31:0] lock_read;
    reg [31:0] addresses [0:63];
    reg [37:0] expected [0:63];
    arm920_tlb_bank dut(.clk(clk),.reset(reset),.lookup(lookup),.lookup_mva(va),
        .result_valid(valid),.result_hit(hit),.result_payload(data),
        .fill(fill),.fill_mva(fill_va),.fill_payload(fill_data),
        .invalidate(inv),.invalidate_mva(by_mva),.invalidate_address(inv_va),
        .lock_write(lock_write),.lock_data(lock_data),.lock_read(lock_read));
    always #5 clk=~clk;
    task tick; begin @(negedge clk); #1; end endtask
    task put(input [31:0] address,input [37:0] value);
        begin fill_va=address;fill_data=value;fill=1;tick();fill=0;tick();end
    endtask
    task check(input [31:0] address,input wanted,input [37:0] value);
        begin
            va=address;lookup=1;tick();lookup=0;tick();
            if (!valid || hit!==wanted || (wanted && data!==value))
                $fatal(1,"CAM result va=%h hit=%b data=%h wanted=%b/%h",address,hit,data,wanted,value);
            tick();
        end
    endtask
    reg [21:0] physical;
    integer n;
    initial begin
        repeat(3)tick();reset=0;tick();
        for(n=0;n<64;n=n+1)begin
            addresses[n]=32'h10000000+n*32'h100000;
            physical=22'h100000+n*1024;
            expected[n]={n[1:0],2'b11,4'b0,8'hff,physical};
            put(addresses[n],expected[n]);
        end
        if(lock_read!==0)$fatal(1,"64 fills did not wrap victim");
        for(n=0;n<64;n=n+1)check(addresses[n]+32'h5c,1,expected[n]);
        put(32'h70000000,{2'd2,36'h1});
        check(addresses[0],0,0);
        for(n=1;n<64;n=n+1)check(addresses[n],1,expected[n]);
        lock_data={6'd4,6'd63,19'b0,1'b1};lock_write=1;tick();lock_write=0;tick();
        put(32'h71000000,{2'd3,36'h2});
        if(lock_read!=={6'd4,6'd4,19'b0,1'b1})$fatal(1,"round robin did not wrap to lockdown base");
        put(32'h72000000,{2'd2,36'h3});
        inv=1;tick();inv=0;tick();
        check(32'h71000000,1,{2'd3,36'h2});check(32'h72000000,1,{2'd2,36'h3});
        check(addresses[1],0,0);
        by_mva=1;inv_va=32'h71000010;inv=1;tick();inv=0;tick();
        check(32'h71000000,0,0);check(32'h72000000,1,{2'd2,36'h3});
        va=32'h72000000;lookup=1;tick();lookup=0;inv=1;tick();inv=0;
        repeat(3)begin if(valid)$fatal(1,"invalidated lookup escaped");tick();end
        $display("PASS: all64 mixed-size entries,65th replacement, lockdown wrap, preserved/all/MVA invalidation, pipeline cancellation");
        $finish;
    end
endmodule
