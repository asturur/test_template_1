`timescale 1ns/1ps
module exercise #(parameter AW=4, DW=16, BW=DW, RO=0, DEPTH=1<<AW)(output reg done=0);
    localparam N=DW/BW;
    reg clk=0;
    always #5 clk=~clk;
    reg [AW-1:0] a=0,b=0;
    reg [DW-1:0] da=0,db=0;
    reg [N-1:0] wa=0,wb=0;
    wire [DW-1:0] qa,qb;
    reg [DW-1:0] expected,old_q;
    ngage_bram #(.AW(AW),.DW(DW),.BYTE_WIDTH(BW),.READ_ONLY_B(RO),.DEPTH(DEPTH)) dut(
        .clk(clk),.addr_a(a),.addr_b(b),.data_a(da),.data_b(db),.we_a(wa),.we_b(wb),.q_a(qa),.q_b(qb));
    task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
    initial begin
        tick();if(qb!==0)$fatal(1,"power-up DW=%0d",DW);
        a=2;b=3;da={DW{1'b1}};wa={N{1'b1}};tick();wa=0;
        // Changing the address cannot change q before a clock edge.
        old_q=qb;b=2;#1;if(qb!==old_q)$fatal(1,"asynchronous read DW=%0d",DW);
        tick();if(qb!=={DW{1'b1}})$fatal(1,"port A write/B read DW=%0d",DW);
        a=2;b=3;da=0;wa=1;tick();wa=0;b=2;tick();
        expected={DW{1'b1}};expected[BW-1:0]=0;
        if(qb!==expected)$fatal(1,"byte-enable preservation DW=%0d got=%h",DW,qb);
        if(!RO)begin
            a=2;b=5;db={DW{1'b1}};wb={N{1'b1}};tick();wb=0;a=5;b=2;tick();
            if(qa!=={DW{1'b1}} || qb!==expected)$fatal(1,"reverse port DW=%0d",DW);
            a=1;b=2;da=0;db={DW{1'b1}};wa={N{1'b1}};wb={N{1'b1}};tick();wa=0;wb=0;
            a=2;b=1;tick();if(qa!=={DW{1'b1}} || qb!==0)$fatal(1,"concurrent ports DW=%0d",DW);
        end
        a=DEPTH-1;b=0;da={DW{1'b1}};wa={N{1'b1}};tick();wa=0;b=DEPTH-1;tick();
        if(qb!=={DW{1'b1}})$fatal(1,"last address DW=%0d",DW);
        done=1;
    end
endmodule
module tb;
    wire [6:0] done;
    exercise #(.DW(1),.DEPTH(13)) bitmap(done[0]);
    exercise #(.AW(8),.DW(16)) sector(done[1]);
    exercise #(.AW(9),.DW(32),.BW(8),.RO(1)) cache(done[2]);
    exercise #(.AW(3),.DW(24),.RO(1)) tags(done[3]);
    exercise #(.AW(9),.DW(27)) physical(done[4]);
    exercise #(.AW(6),.DW(84),.RO(1)) trace_ring(done[5]);
    exercise #(.AW(5),.DW(24),.RO(1),.DEPTH(19)) lcd(done[6]);
    initial begin wait(&done);$display("PASS explicit BRAM widths, ports, byte enables, depth and read latency");$finish;end
    initial begin #2000;$fatal(1,"BRAM timeout");end
endmodule
