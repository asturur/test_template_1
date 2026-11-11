`timescale 1ns/1ps
module fence_tb;
    reg clk=0,reset=1;
    always #5 clk=~clk;
    reg req=0,commit=0,we=0;
    reg [31:0] addr=0,din=0;
    wire claim,bad;
    wire [31:0] dout;
    wire [7:0] irq_pending,error_pending,active_channels;
    reg queued=0;
    wire cmd_valid,cmd_ready,cmd_write;
    wire [31:0] cmd_addr,cmd_data;
    wire [3:0] cmd_be;
    reg rsp_valid=0;
    integer writes=0,phase;
    assign cmd_ready=!rsp_valid;
    ngage_dma_channels #(.ENGINES(1),.PRODUCTION(1)) dut (
        .clk(clk),.reset(reset),.req(req),.commit(commit),.we(we),.addr(addr),.din(din),.sel(4'hf),
        .claim(claim),.bad(bad),.dout(dout),.irq_pending(irq_pending),.error_pending(error_pending),.active_channels(active_channels),
        .lcd_ready(!queued),.lcd_drained(!queued),.source_ready(8'hff),.destination_ready(8'hff),
        .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_write(cmd_write),.cmd_addr(cmd_addr),.cmd_data(cmd_data),.cmd_be(cmd_be),
        .rsp_valid(rsp_valid),.rsp_error(1'b0),.rsp_data(32'h01230abc)
    );
    always @(posedge clk)begin
        rsp_valid<=0;
        if(!reset && cmd_valid && cmd_ready)begin
            rsp_valid<=1;
            if(cmd_write)begin
                if(queued || cmd_addr!=32'h10121208 || cmd_be!=15 || cmd_data!=32'h01230abc)$fatal(1,"bad queued word");
                queued<=1;
                writes<=writes+1;
            end
        end
    end
    task wr;
        input [31:0] a,d;
        begin
            @(negedge clk);req=1;commit=1;we=1;addr=a;din=d;
            #1;if(!claim || bad)$fatal(1,"register decode %h",a);
            @(negedge clk);req=0;commit=0;
        end
    endtask
    task program_word;
        begin
            wr(32'h0c120064,7);
            wr(32'h0c120304,1);
            // On-chip RAM requires the general route; eligible SDRAM uses
            // the stream automatically in production.
            wr(32'h0c120314,32'h0c004100);
            wr(32'h0c120318,1);
            wr(32'h0c12031c,32);
            wr(32'h0c120320,32'h10121208);
            wr(32'h0c120324,0);
            wr(32'h0c120328,32);
            wr(32'h0c12032c,0);
            wr(32'h0c120308,2);
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);reset=0;
        for(phase=0;phase<3;phase=phase+1)begin
            program_word();
            // Stop/restart exactly on RUN's final done-generation edge,
            // before the scheduler has observed the engine's done pulse.
            while(!(dut.engines[0].engine.state==1 &&
                dut.engines[0].engine.source_left==0 && dut.engines[0].engine.fill==0))@(negedge clk);
            if(!queued)$fatal(1,"no accepted queued tail");
            req=1;commit=1;we=1;addr=32'h0c120308;din=phase==1?2:0;
            @(negedge clk);req=0;commit=0;
            repeat(8)@(negedge clk);
            if(active_channels!=1 || irq_pending!=0 || error_pending!=0)$fatal(1,"terminal cancel lost fence phase%0d",phase);
            if(phase==2)begin
                reset=1;@(negedge clk);queued=0;reset=0;
                repeat(5)@(negedge clk);
                if(active_channels || irq_pending || cmd_valid)$fatal(1,"reset completion leakage");
            end else begin
                queued=0;
                if(phase==1)begin
                    wait(writes==3);
                    repeat(8)@(negedge clk);
                    if(active_channels!=1 || irq_pending!=0)$fatal(1,"replacement completed before its pixel");
                    queued=0;
                    wait(irq_pending==1);
                    wr(32'h0c120304,0);
                end
                repeat(5)@(negedge clk);
                if(active_channels || irq_pending)$fatal(1,"stale completion after drain");
            end
        end
        $display("PASS production DMA final-response stop/restart cancellation fence and reset");$finish;
    end
    initial begin #100000;$fatal(1,"fence timeout phase %0d writes%0d active%h irq%h",phase,writes,active_channels,irq_pending);end
endmodule
