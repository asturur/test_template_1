`timescale 1ns/1ps
module tb;
    reg clk=0,reset=1,tick=0,req=0,commit=0,we=0;
    reg [31:0] addr=0,din=0;
    reg [3:0] sel=15;
    always #5 clk=~clk;
    wire claim,bad,ready;
    wire [31:0] dout;
    wire [15:0] events;
    integer clocks=0,i,j,start,producer,response_start,response_end,read_done,wrapping;
    reg [15:0] query[0:5],reply[0:5];
    reg [31:0] value;
    integer received_irqs=0,consumed_irqs=0;
    ngage_upp_mdi #(.ANNOUNCE_TICKS(2)) dut(
        .clk(clk),.reset(reset),.tick(tick),.periodic_active(1'b1),
        .req(req),.commit(commit),.we(we),.addr(addr),.din(din),.sel(sel),
        .claim(claim),.bad(bad),.ready(ready),.dout(dout),.irq_events(events)
    );
    always @(posedge clk) begin
        clocks<=clocks+1;
        if(events[9]) consumed_irqs<=consumed_irqs+1;
        if(events[10]) received_irqs<=received_irqs+1;
        if(clocks>100000) $fatal(1,"MDI timeout");
    end
    task access;
        input [31:0] a,d;
        input w;
        input [3:0] lanes;
        begin
            @(negedge clk);req=1;commit=0;we=w;addr=a;din=d;sel=lanes;
            #1;
            while(!ready) begin @(negedge clk);#1;end
            if(!claim||bad)$fatal(1,"MDI rejected %h lanes%h",a,lanes);
            value=dout;
            commit=1;
            @(negedge clk);req=0;commit=0;
        end
    endtask
    task word_write;
        input [31:0] a,d;
        begin access(a,d,1,15);end
    endtask
    task half_write;
        input [31:0] a;
        input [15:0] d;
        begin access(a,a[1]?{d,16'b0}:{16'b0,d},1,a[1]?12:3);end
    endtask
    task half_read;
        input [31:0] a;
        begin
            access(a,0,0,a[1]?12:3);
            value=a[1]?value>>16:value;
        end
    endtask
    task query_write;
        input integer base;
        begin
            for(j=0;j<6;j=j+1)half_write(32'h0c100000+2*((base+j)%250),query[j]);
            producer=(base+6)%250;
            half_write('h0c1003e8,producer);
        end
    endtask
    task wait_reply;
        input integer expected;
        integer waits;
        begin
            waits=0;
            while(dut.receive_ptr[15:0]!=expected)begin
                @(negedge clk);waits=waits+1;
                if(waits>2000)$fatal(1,"no MDI reply expected%0d got%0d state%0d wp%0d rp%0d",expected,dut.receive_ptr[15:0],dut.state,dut.pointers[15:0],dut.pointers[31:16]);
            end
        end
    endtask
    task verify_reply;
        input integer base;
        begin
            for(j=0;j<6;j=j+1)begin
                half_read(32'h0c1001f4+2*((base+j)%250));
                if(value[15:0]!==reply[j])$fatal(1,"MDI response half%0d got%h expected%h",j,value[15:0],reply[j]);
            end
        end
    endtask
    initial begin
        // Hardware halfwords emitted by the unmodified native TX task.
        query[0]='h007c;query[1]='h00f1;query[2]='h0006;
        query[3]='h2a1b;query[4]='h20a0;query[5]='h0200;
        reply[0]='h0000;reply[1]='h7cf1;reply[2]='h0006;
        reply[3]='h1b2a;reply[4]='h20a1;reply[5]='h0103;
        for(wrapping=0;wrapping<2;wrapping=wrapping+1)begin
            req=0;commit=0;reset=1;repeat(3)@(negedge clk);reset=0;
            start=wrapping?247:0;
            response_start=wrapping?243:0;
            word_write('h0c1003e8,(start<<16)|start);
            word_write('h0c1003ec,(response_start<<16)|response_start);
            word_write('h0c14b004,'h500);
            tick=1;repeat(3)@(negedge clk);tick=0;
            response_start=(response_start+4)%250;
            wait_reply(response_start);
            // Consume the preserved native link-start announcement.
            half_write('h0c1003ee,response_start);
            query_write(start);
            response_end=(response_start+6)%250;
            wait_reply(response_end);
            verify_reply(response_start);
            if(dut.pointers[31:16]!=producer)$fatal(1,"M2D was not consumed");
            half_write('h0c1003ee,response_end);
        end
        // Fill the reply ring naturally; the next reply must wait for space.
        for(i=0;i<41;i=i+1)begin
            response_start=response_end;
            query_write(producer);
            response_end=(response_start+6)%250;
            wait_reply(response_end);
        end
        response_start=response_end;
        query_write(producer);
        repeat(150)@(negedge clk);
        if(dut.receive_ptr[15:0]!=response_start)$fatal(1,"full reply ring overwritten");
        // Release one complete response, then verify the pending reply.
        read_done=(dut.receive_ptr[31:16]+6)%250;
        half_write('h0c1003ee,read_done);
        response_end=(response_start+6)%250;
        wait_reply(response_end);
        verify_reply(response_start);
        // Reset cancels all protocol state and published pointers.
        reset=1;@(negedge clk);reset=0;repeat(6)@(negedge clk);
        if(dut.pointers!=0||dut.receive_ptr!=0||events!=0)$fatal(1,"MDI reset leaked work");
        if(received_irqs<40||consumed_irqs<200)$fatal(1,"MDI event coverage");
        $display("PASS UPP MDI native halfwords,250-word wrap, BRAM read latency, reply backpressure, publication, IRQ events and reset");
        $finish;
    end
endmodule
