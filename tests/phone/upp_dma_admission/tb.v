`timescale 1ns/1ps
module tb;
    reg clk=0, reset=1, waiting=0, window_ready=1, endpoint_ready=0;
    wire ready, exclude;
    ngage_upp_dma_admission dut (.clk(clk),.reset(reset),.waiting(waiting),.window_ready(window_ready),.endpoint_ready(endpoint_ready),.ready(ready),.exclude_cpu(exclude));
    task tick; begin #2;clk=1;#2;clk=0;#2;end endtask
    initial begin
        tick;reset=0;
        // Native MMC retains its external reservation and immediate handshake.
        endpoint_ready=1;#1;if(!ready || exclude)$fatal(1,"native MMC gained a stage");
        endpoint_ready=0;#1;if(ready || exclude)$fatal(1,"unready MMC admitted");
        waiting=1;tick;
        endpoint_ready=1;#1;if(ready || exclude)$fatal(1,"live readiness leaked into generic grant");
        tick;if(!ready || !exclude)$fatal(1,"generic packet not granted after sample");
        // Endpoint withdraws after a positive sample: do not accept; release
        // CPU exclusion on the next edge so software can stop/reconfigure it.
        endpoint_ready=0;#1;if(ready || !exclude)$fatal(1,"stale sample accepted or live path restored");
        tick;if(ready || exclude)$fatal(1,"backpressure retained CPU indefinitely");
        repeat(4)begin tick;if(ready || exclude)$fatal(1,"waiting full endpoint blocked CPU");end
        endpoint_ready=1;tick;
        window_ready=0;#1;if(ready || exclude)$fatal(1,"CPU lock/busy window bypassed");
        window_ready=1;#1;if(!ready || !exclude)$fatal(1,"idle admission did not resume");
        waiting=0;#1;if(!ready || exclude)$fatal(1,"old generic exclusion borrowed next owner");
        tick;waiting=1;#1;if(ready || exclude)$fatal(1,"old sample borrowed new generic owner");
        tick;reset=1;#1;if(ready || exclude)$fatal(1,"reset leaked admission");
        tick;reset=0;#1;if(ready || exclude)$fatal(1,"reset retained sample");
        tick;if(!ready || !exclude)$fatal(1,"restart after reset");
        $display("PASS DMA admission: native MMC immediate, generic sample, backpressure/CPU progress, owner gap, busy/lock and reset");$finish;
    end
endmodule
