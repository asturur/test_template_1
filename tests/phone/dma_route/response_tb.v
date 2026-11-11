`timescale 1ns/1ps
// The new local response stage owns the exact accepted data/error. RAM bypass
// keeps its original response cycle; reset kills a captured local completion.
module response_tb;
    reg clk=0, reset=1, lock=0, valid=0, local_ready=0, local_done=0, local_error=0, ram_ack=0;
    reg [31:0] address=0, local_data=0;
    reg [3:0] mask=15;
    wire ready, response, error, local_valid;
    wire [31:0] data;
    always #5 clk=~clk;
    ngage_dma_route dut (
        .clk(clk), .reset(reset), .cpu_lock(lock),
        .cmd_valid(valid), .cmd_ready(ready), .cmd_write(1'b0),
        .cmd_addr(address), .cmd_data(32'b0), .cmd_be(mask),
        .rsp_valid(response), .rsp_error(error), .rsp_data(data),
        .ram_ack(ram_ack), .ram_rdata(32'h12345678),
        .local_valid(local_valid), .local_ready(local_ready),
        .local_done(local_done), .local_error(local_error), .local_rdata(local_data)
    );
    task tick; begin @(posedge clk); #1; @(negedge clk); end endtask
    integer failed;
    initial begin
        tick(); reset=0;
        local_done=1; local_error=1; local_data=32'hbad00000;
        tick(); if(response) $fatal(1,"unsolicited local ACK escaped IDLE");
        local_done=0;
        for(failed=0; failed<2; failed=failed+1) begin
            address=32'h0c004020; mask=15; valid=1; local_ready=0;
            #1; if(!ready) $fatal(1,"local request capture blocked");
            tick(); valid=0;
            repeat(3) begin tick(); if(response || !local_valid) $fatal(1,"waiting local packet lost"); end
            local_ready=1; local_done=1; local_error=failed; local_data=32'habc00000+failed;
            #1; if(response) $fatal(1,"local decode still reaches response combinationally");
            tick(); local_done=0; local_error=!failed; local_data=32'hdeadbeef; lock=1;
            #1; if(!response || error!==failed[0] || data!==(32'habc00000+failed) || ready || local_valid)
                $fatal(1,"captured local response identity/ownership changed");
            tick(); lock=0;
            #1; if(response || !ready) $fatal(1,"local response was not exactly one cycle");
        end
        // A FIFO can accept and complete on the original request edge.
        address=32'h0c120624; mask=1; valid=1; local_ready=1; local_done=1; local_error=0; local_data=32'h55;
        #1; if(!ready || response) $fatal(1,"FIFO capture contract");
        tick(); valid=0; local_done=0;
        #1; if(!response || data!==32'h55) $fatal(1,"same-edge FIFO result lost");
        reset=1; #1; if(response) $fatal(1,"reset exposed queued response");
        tick(); reset=0; tick(); if(response) $fatal(1,"reset replayed queued response");
        address=32'h0a000000; mask=15; valid=1;
        tick(); valid=0; ram_ack=1;
        #1; if(!response || error || data!==32'h12345678) $fatal(1,"RAM acquired an extra response cycle");
        tick(); ram_ack=0;
        #1; if(response || !ready) $fatal(1,"RAM completion not released");
        $display("PASS local DMA registered response: exact data/error, stalls, CPU lock, FIFO same-edge capture, stale ACK/reset and unchanged RAM cycle");
        $finish;
    end
    initial begin #20000; $fatal(1,"timeout"); end
endmodule
