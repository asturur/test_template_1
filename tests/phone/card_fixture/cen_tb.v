`timescale 1ns/1ps
module tb;
    reg clk=0,reset=1,tx=0,pop=0;
    reg [7:0] data=0;
    wire slow_valid,fast_valid,slow_overflow,fast_overflow,slow_emit,fast_emit,busy,fast_busy;
    wire [7:0] slow_data,fast_data;
    wire [6:0] slow_count,fast_count;
    integer cycles=0,last_cen=-1,n,j,waits;
    reg [6:0] old_count;
    always #5 clk=~clk;
    ngage_test_sim #(.CLOCK_DIV(32)) slow(clk,reset,tx,data,pop,slow_valid,slow_data,slow_overflow,slow_count,slow_emit,busy);
    ngage_test_sim fast(clk,reset,tx,data,pop,fast_valid,fast_data,fast_overflow,fast_count,fast_emit,fast_busy);
    always @(posedge clk)begin
        cycles=cycles+1;
        if(reset)last_cen=-1;
        else if(slow.cen)begin
            if(last_cen>=0 && cycles-last_cen!=32)$fatal(1,"SIM enable spacing");
            last_cen=cycles;
        end
    end
    task event_step;
        input transmit;
        input [7:0] value;
        input receive;
        begin
            @(negedge clk);tx=transmit;data=value;pop=receive;old_count=slow_count;
            #1;if(slow_emit!==fast_emit)$fatal(1,"SIM response prediction");
            @(posedge clk);#1;
            if(!busy || slow_count!==old_count)$fatal(1,"event did not cross register");
            @(negedge clk);tx=0;pop=0;data=~value;waits=0;
            while(busy)begin @(negedge clk);waits=waits+1;if(waits>64)$fatal(1,"SIM event stalled");end
            #1;if(slow_count!==fast_count || slow_valid!==fast_valid || slow_overflow!==fast_overflow || slow_data!==fast_data)
                $fatal(1,"SIM enabled/fast mismatch n=%0d count=%d/%d data=%h/%h",n,slow_count,fast_count,slow_data,fast_data);
        end
    endtask
    initial begin
        repeat(2)@(negedge clk);reset=0;
        for(n=0;n<160;n=n+1)begin
            // Long responses fill/wrap/saturate the queue; pop and transmit
            // together to cover space released on the same service edge.
            event_step(1,8'ha0,n&1);event_step(1,8'hf2,n&1);
            event_step(1,0,n&1);event_step(1,0,n&1);event_step(1,22,n&1);
            for(j=0;j<n%39;j=j+1)event_step(0,0,1);
        end
        repeat(64)event_step(0,0,1);
        // Reset cancels a captured event before its enable arrives.
        @(negedge clk);tx=1;data=8'ha0;@(negedge clk);tx=0;reset=1;
        @(negedge clk);reset=0;#1;
        if(busy || slow_count!=0 || slow_overflow)$fatal(1,"SIM reset did not cancel event");
        $display("PASS SIM 3.25 MHz enable: registered events, 32-clock cadence, data capture, FIFO equivalence and reset");
        $finish;
    end
endmodule
