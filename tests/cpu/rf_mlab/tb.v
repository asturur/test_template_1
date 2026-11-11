`timescale 1ns/1ps
module tb;
    reg clk=0, reset=1, wen=0;
    reg [5:0] wa=0, wb=0;
    reg [39:0] wc=0;
    reg [31:0] da=0, db=0, dc=0;
    reg [5:0] rd [0:4];
    wire [31:0] q [0:4];
    reg [31:0] model [0:39];
    reg [31:0] rng=32'h9357da12;
    integer n, p, r, checks=0;
    zap_register_file dut (
        .i_clk(clk),.i_reset(reset),.i_wen(wen),
        .i_wr_addr_a(wa),.i_wr_addr_b(wb),.i_wr_addr_c(wc),
        .i_wr_data_a(da),.i_wr_data_b(db),.i_wr_data_c(dc),
        .i_rd_addr_a(rd[0]),.i_rd_addr_b(rd[1]),.i_rd_addr_c(rd[2]),.i_rd_addr_d(rd[3]),.i_rd_addr_cp15(rd[4]),
        .o_rd_data_a(q[0]),.o_rd_data_b(q[1]),.o_rd_data_c(q[2]),.o_rd_data_d(q[3]),.o_rd_data_cp15(q[4])
    );
    function [31:0] random_word;
        input [31:0] x;
        begin random_word=x^(x<<13); random_word=random_word^(random_word>>17); random_word=random_word^(random_word<<5); end
    endfunction
    task check;
        begin
            #2;
            for(p=0;p<5;p=p+1) begin
                if(q[p] !== model[rd[p]]) $fatal(1,"RF n=%0d port=%0d index=%0d actual=%h expected=%h",n,p,rd[p],q[p],model[rd[p]]);
                `ifndef SYNTHESIS
                if(dut.mem[rd[p]] !== model[rd[p]]) $fatal(1,"architectural RF debug tap");
`endif
                checks=checks+1;
            end
        end
    endtask
    task tick;
        begin
            check;
            if(reset) for(r=0;r<40;r=r+1) model[r]=0;
            else begin
                if(wen) begin
                    if(wa<40)model[wa]=da;
                    if(wb<40)model[wb]=db;
                end
                for(r=0;r<40;r=r+1)if(wc[r])model[r]=dc;
            end
            clk=1; check; clk=0;
        end
    endtask
    initial begin
        for(p=0;p<5;p=p+1)rd[p]=0;
        // First edge establishes the architectural reset state.
        clk=1; #2; clk=0;
        for(r=0;r<40;r=r+1) model[r]=0;
        for(n=0;n<20000;n=n+1)begin
            rng=random_word(rng);wen=rng[0];wa=rng[7:2];wb=rng[13:8];
            rng=random_word(rng);da=rng;rng=random_word(rng);db=rng;rng=random_word(rng);dc=rng;
            wc=n%5==0?40'hffffffffff:n%3==0?((40'b1<<(wa%40))|(40'b1<<(wb%40))):0;
            reset=n%127==0;
            if(n%7==0)wb=wa;
            for(p=0;p<5;p=p+1)begin rng=random_word(rng);rd[p]=rng%40;end
            if(n%2==0)begin rd[0]=wa%40;rd[1]=wb%40;end
            tick;
        end
        wen=0;wc=0;reset=0;
        for(n=0;n<40;n=n+1)begin for(p=0;p<5;p=p+1)rd[p]=n;tick;end
        $display("PASS RF independent scoreboard: %0d pre/post-edge reads; resets, A/B/C priority, multi-bit C, invalid writes, all five ports",checks);
        $finish;
    end
endmodule
