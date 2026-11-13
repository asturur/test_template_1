`timescale 1ns/1ps
module tb;
parameter DEPTH=6;
reg clk=0;
always #5 clk=~clk;
reg reset=1, dirty=0, flush=0, abort=0;
reg [2:0] index=0;
reg [3:0] limit=0;
wire [31:0] debug_state;
wire initialized, flushing, failed, fault, pending, offered;
wire [2:0] sector;
reg accept=0, done=0, ok=1;

ngage_ordered_dirty_queue #(.SECTORS(6), .AW(3), .DEPTH(DEPTH)) dut (
    .clk(clk),.cold_reset(reset),.dirty_valid(dirty),.dirty_sector(index),
    .flush_start(flush),.flush_limit(limit),.abort_flush(abort),
    .init_done(initialized),.flushing(flushing),.flush_error(failed),
    .queue_fault(fault),.debug_state(debug_state),.pending(pending),.sector_valid(offered),.sector_index(sector),
    .sector_accept(accept),.sector_done(done),.sector_ok(ok)
);
task automatic mark(input [2:0] n);
    index=n; dirty=1;
    @(negedge clk);
    dirty=0;
endtask
task automatic start(input [3:0] n);
    limit=n; flush=1;
    @(negedge clk);
    flush=0;
endtask
task automatic expect_offer(input [2:0] n);
    while (!offered) @(negedge clk);
    if (sector!==n || failed || fault) $fatal(1,"expected sector %0d got %0d",n,sector);
endtask
task automatic take;
    accept=1;
    @(negedge clk);
    accept=0;
endtask
task automatic finish(input bit success);
    done=1; ok=success;
    @(negedge clk);
    done=0;
endtask
task automatic service(input [2:0] n);
    expect_offer(n);
    take();
    finish(1);
endtask
task automatic drain_complete(input bit still_pending);
    while(flushing) @(negedge clk);
    if (pending!==still_pending || offered || fault || failed)
        $fatal(1,"wrong batch completion");
endtask

reg [2:0] expected [0:5];
integer expected_count=0, observed_count=0;
reg prior_mark=0, waiting_ack=0;
reg [2:0] prior_index=0;
reg [31:0] pattern=32'h8127d5ef;
task automatic model_step;
    bit was_offered, duplicate;
    was_offered=offered;
    if (done) waiting_ack=0;
    if (offered && accept) waiting_ack=1;
    @(posedge clk); #1;
    if (offered && !was_offered) begin
        if (expected_count==0 || sector!==expected[0])
            $fatal(1,"randomized order mismatch sector %0d",sector);
        for (integer j=1;j<expected_count;j++) expected[j-1]=expected[j];
        expected_count--;
        observed_count++;
    end
    if (prior_mark) begin
        duplicate=0;
        for (integer j=0;j<expected_count;j++)
            if (expected[j]==prior_index) duplicate=1;
        if (!duplicate) begin
            if (expected_count==6) $fatal(1,"reference queue overflow");
            expected[expected_count]=prior_index;
            expected_count++;
        end
    end
    prior_mark=dirty;
    prior_index=index;
    if (failed || fault) $fatal(1,"randomized stream failed");
    @(negedge clk);
endtask

task automatic random_order;
    for (integer i=0;i<3000;i++) begin
        pattern=pattern ^ (pattern << 13);
        pattern=pattern ^ (pattern >> 17);
        pattern=pattern ^ (pattern << 5);
        dirty=pattern[1:0]!=0;
        index=3'(pattern[11:4]%6);
        flush=!flushing && pattern[12];
        limit={2'b0,pattern[14:13]};
        accept=offered && pattern[15];
        done=waiting_ack && pattern[16];
        ok=1;
        model_step();
    end
    dirty=0;
    limit=0;
    while (pending || flushing || prior_mark) begin
        flush=!flushing && pending;
        accept=offered;
        done=waiting_ack;
        model_step();
    end
    flush=0; accept=0; done=0;
    if (expected_count!=0 || observed_count<100)
        $fatal(1,"randomized order coverage or drain");
    $display("PASS ordered dirty queue randomized reference, %0d offers",observed_count);
endtask

initial begin
    repeat(3) @(negedge clk);
    reset=0;
    wait(initialized);
    @(negedge clk);
    if (DEPTH<6) begin
        mark(2); mark(4); mark(1); mark(0);
        repeat(4) @(negedge clk);
        if (!fault || !failed || !pending || debug_state[31:24]!=8'h51 || debug_state[1:0]!=2'b10 || debug_state[23:9]!=DEPTH) $fatal(1,"overflow did not fail closed");
        start(0);
        repeat(4) @(negedge clk);
        if (offered || flushing || !pending) $fatal(1,"overflow silently changed order");
        $display("PASS ordered dirty queue explicit overflow retention");
        $finish;
    end
    // Same-sector consecutive inputs, cross-region order, and marks while
    // offered, in flight, and coincident with successful HPS completion.
    mark(4); mark(4); mark(1); mark(3); mark(1);
    start(2);
    expect_offer(4);
    mark(4);
    take();
    mark(0); mark(4);
    index=4; dirty=1; finish(1); dirty=0;
    expect_offer(1);
    take();
    mark(1);
    finish(1);
    drain_complete(1);
    start(0);
    service(3); service(4); service(0); service(1);
    drain_complete(0);

    // Every sector can be pending at once. The active sector can obtain
    // another generation even with a full ring. Repeat after pointer wrap.
    for (integer pass=0;pass<4;pass++) begin
        for (integer j=0;j<6;j++) mark(3'((j+2)%6));
        for (integer j=0;j<6;j++) mark(3'(j));
        start(0);
        expect_offer(2);
        mark(2);
        take();
        finish(1);
        for (integer j=1;j<6;j++) service(3'((j+2)%6));
        service(2);
        drain_complete(0);
    end
    // Mark is sampled one clock before the full-queue dequeue. Enqueue
    // the new generation on exactly the same edge as the old one leaves.
    for (integer j=0;j<6;j++) mark(3'(j));
    repeat(3) @(negedge clk);
    index=0; dirty=1;
    start(0);
    dirty=0;
    service(0);
    for (integer j=1;j<6;j++) service(3'(j));
    service(0);
    drain_complete(0);

    random_order();
    mark(5); mark(2); start(0);
    expect_offer(5); take(); finish(0);
    if (flushing || offered || !pending || !failed || fault)
        $fatal(1,"failed host ACK lost active or queued work");
    start(0); repeat(8) @(negedge clk);
    if (flushing || offered || !pending || !failed)
        $fatal(1,"terminal transfer retried");
    $display("PASS ordered dirty queue generations, order, full capacity, wrap, batch and failed ACK");
    $finish;
end
initial begin
    #100000;
    $fatal(1,"ordered dirty queue timeout");
end
endmodule
