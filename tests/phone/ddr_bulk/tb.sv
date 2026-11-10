`timescale 1ns/1ps
module tb;
localparam [31:0] BASE = 32'h31400000;
reg clk = 0;
always #5 clk = !clk;
reg reset = 1, lock = 0, cpu = 0, cpu_write = 0, save = 0;
reg [31:0] cpu_addr = BASE, cpu_data = 0;
wire cpu_ready, cpu_done, save_ready, save_done;
wire [31:0] cpu_result;
wire request, ready, writing, bulk, done;
wire [31:0] address, data, result;
wire [3:0] mask;
wire beat_valid, beat_last, bulk_error;
reg consume = 0, pause_ddr = 0;
wire [63:0] beat, physical_data;
wire [28:0] physical_address;
wire [7:0] physical_mask, burst;
wire rd, wr;
reg [63:0] physical_read = 0;
reg physical_valid = 0;
reg [63:0] memory [0:63];
integer remaining = 0, cursor = 0, snapshots = 0, writes = 0;
integer seen = 0, cycles = 0;
reg check_snapshot = 0;
reg [63:0] first = 64'h1234abcd0000face;

ngage_ddr_arbiter arbiter (
    .clk(clk), .reset(reset), .cpu_lock(lock), .l_bulk(1'b1), .c_bulk(1'b0),
    .l_valid(save), .l_ready(save_ready), .l_addr(BASE), .l_data(32'b0),
    .l_be(4'hf), .l_write(1'b0), .l_done(save_done),
    .c_line(1'b0), .c_valid(cpu), .c_ready(cpu_ready), .c_addr(cpu_addr),
    .c_data(cpu_data), .c_be(4'hf), .c_write(cpu_write), .c_done(cpu_done),
    .c_rdata(cpu_result), .req_valid(request), .req_ready(ready),
    .req_addr(address), .req_data(data), .req_be(mask), .req_write(writing),
    .req_bulk(bulk), .rsp_valid(done), .rsp_data(result),
    .rsp_beat_valid(1'b0), .rsp_beat_data(64'b0), .rsp_beat_last(1'b0)
);
ngage_ddr_flash_adapter #(
    .BULK_PERSISTENCE(1), .STREAM_TRANSPORT(1), .FLASH_CACHE_BYTES(8192)
) dut (
    .clk(clk), .reset(reset), .req_valid(request), .req_ready(ready),
    .req_addr(address), .req_wdata(data), .req_be(mask), .req_write(writing),
    .req_bulk(bulk), .req_line(1'b0), .req_fetch(1'b0),
    .rsp_valid(done), .rsp_data(result),
    .bulk_cancel(1'b0), .bulk_error(bulk_error),
    .bulk_read_valid(beat_valid), .bulk_read_ready(consume),
    .bulk_read_data(beat), .bulk_read_last(beat_last),
    .bulk_write_valid(1'b0), .bulk_write_data(64'b0), .bulk_write_last(1'b0),
    .ddr_addr(physical_address), .ddr_burstcount(burst), .ddr_rd(rd), .ddr_we(wr),
    .ddr_din(physical_data), .ddr_be(physical_mask), .ddr_busy(1'b0),
    .ddr_dout(physical_read), .ddr_dout_ready(physical_valid)
);

always @(posedge clk) begin
    cycles <= cycles + 1;
    physical_valid <= 0;
    if (rd) begin
        if (remaining || (burst != 4 && burst != 64))
            $fatal(1, "overlapping DDR commands");
        if ({physical_address,3'b0} != BASE)
            $fatal(1, "unexpected backing address");
        remaining <= int'(burst);
        cursor <= 0;
        if (burst == 64) snapshots <= snapshots + 1;
    end
    if (remaining && !pause_ddr && cycles % 3 != 1) begin
        physical_read <= memory[cursor];
        physical_valid <= 1;
        cursor <= cursor + 1;
        remaining <= remaining - 1;
    end
    if (wr) begin
        if (remaining || burst != 1 || {physical_address,3'b0} != BASE)
            $fatal(1, "write overtook snapshot");
        for (integer j = 0; j < 8; j++)
            if (physical_mask[j]) memory[0][8*j+:8] <= physical_data[8*j+:8];
        writes <= writes + 1;
    end
    if (check_snapshot && beat_valid && consume) begin
        if (seen >= 64 || beat !== first+64'(seen) || beat_last !== (seen == 63))
            $fatal(1, "snapshot bytes/order %0d", seen);
        seen <= seen + 1;
    end
    if (check_snapshot && cpu_ready) $fatal(1, "CPU admitted before final snapshot beat");
end

task automatic request_cpu_read;
    @(negedge clk);
    cpu = 1;
    cpu_write = 0;
    do @(posedge clk); while (!cpu_ready);
    @(negedge clk);
    cpu = 0;
    wait(cpu_done);
endtask

initial begin
    for (integer j = 0; j < 64; j++) memory[j] = first+64'(j);
    repeat (4) @(negedge clk);
    reset = 0;

    // Offer a sector after the CPU has received its word but before the
    // previously accepted D2 fill has completed.
    fork
        request_cpu_read();
        begin
            wait(physical_valid);
            @(negedge clk);
            pause_ddr = 1;
        end
    join
    if (cpu_result !== first[31:0] || remaining != 3) $fatal(1, "word did not return early");
    @(negedge clk);
    save = 1;
    lock = 1;
    repeat (6) begin
        @(negedge clk);
        if (save_ready || rd) $fatal(1, "SWP or previous fill lost ownership");
    end
    lock = 0;
    repeat (6) begin
        @(negedge clk);
        if (save_ready || rd) $fatal(1, "sector overtook D2 tail");
    end
    pause_ddr = 0;
    do @(posedge clk); while (!save_ready);
    @(negedge clk);
    save = 0;
    check_snapshot = 1;
    cpu = 1;
    cpu_write = 1;
    cpu_data = 32'h87654321;
    // Keep the whole physical burst buffered, then consume it.
    wait(snapshots == 1 && remaining == 0);
    repeat (5) @(negedge clk);
    if (save_done || !beat_valid || beat !== first || writes)
        $fatal(1, "stalled snapshot lost ownership");
    consume = 1;
    wait(save_done);
    @(negedge clk);
    if (seen != 64 || bulk_error) $fatal(1, "snapshot completed early");
    check_snapshot = 0;
    do @(posedge clk); while (!cpu_ready);
    @(negedge clk);
    cpu = 0;
    wait(cpu_done);
    @(negedge clk);
    if (memory[0] !== {first[63:32],32'h87654321} || writes != 1)
        $fatal(1, "queued write missing");
    consume = 0;
    @(negedge clk);
    save = 1;
    do @(posedge clk); while (!save_ready);
    @(negedge clk);
    save = 0;
    wait(beat_valid);
    @(negedge clk);
    pause_ddr = 1;
    reset = 1;
    repeat (3) @(negedge clk);
    reset = 0;
    cpu = 1;
    cpu_write = 0;
    // Even after the cache reset sweep, a sector's pending physical tail
    // still owns the mux.
    repeat (280) begin
        @(negedge clk);
        if (cpu_ready || beat_valid || cpu_done || save_done || rd || wr)
            $fatal(1, "reset let another client overtake the old sector");
    end
    pause_ddr = 0;
    do @(posedge clk); while (!cpu_ready);
    @(negedge clk);
    cpu = 0;
    wait(cpu_done);
    if (cpu_result !== 32'h87654321 || snapshots != 2)
        $fatal(1, "stale bulk tail contaminated new scalar read");
    $display("PASS D3 DDR ownership, SWP, D2 tail, stalled snapshot, queued mutation and reset drain");
    $finish;
end

initial begin
    #1000000;
    $fatal(1, "D3 DDR timeout");
end
endmodule
