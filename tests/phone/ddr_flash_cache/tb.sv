`timescale 1ns/1ps
module tb;
parameter CACHE_BYTES = 8192, STREAM_TRANSPORT = 0;
localparam ROM = 32'h30000000, C = 32'h31400000, PMM = 32'h31800000, TRACE = 32'h31f00000;
reg clk = 0;
always #5 clk = !clk;
reg reset = 1, request = 0, writing = 0, line = 0;
reg [31:0] address = 0, write_data = 0;
reg [3:0] mask = 0;
wire ready, done, beat_valid, beat_last, rd, wr;
wire [31:0] result;
wire [63:0] beat_data, phy_write;
wire [28:0] phy_addr;
wire [7:0] phy_be, burst;
reg [63:0] phy_read = 0;
reg phy_valid = 0, pause_beats = 0;
integer cycle = 0, reads = 0, writes = 0, remaining = 0;
reg [28:0] next_beat;
reg [31:0] dram [0:65535], reference [0:65535];
integer completed = 0, clocks = 0, count = 0, index;
integer word_hit_clocks = 0, word_miss_clocks = 0, word_hits = 0, word_misses = 0;
reg measure = 0;
wire busy = !measure && (cycle % 7 == 2 || cycle % 7 == 3);

ngage_ddr_flash_adapter #(
    .FLASH_CACHE_BYTES(CACHE_BYTES), .STREAM_TRANSPORT(STREAM_TRANSPORT), .LINE_REFILL(1)
) dut (
    .clk(clk), .reset(reset), .req_valid(request), .req_ready(ready), .req_write(writing),
    .req_addr(address), .req_wdata(write_data), .req_be(mask), .req_fetch(1'b0), .req_line(line),
    .rsp_valid(done), .rsp_data(result), .rsp_beat_valid(beat_valid), .rsp_beat_data(beat_data),
    .rsp_beat_last(beat_last), .ddr_addr(phy_addr), .ddr_din(phy_write), .ddr_be(phy_be),
    .ddr_rd(rd), .ddr_we(wr), .ddr_busy(busy), .ddr_dout(phy_read), .ddr_dout_ready(phy_valid),
    .ddr_burstcount(burst)
);

function automatic integer word_index(input [31:0] a);
    // Nonoverlapping fixture windows with room for the largest tag alias.
    if (a >= TRACE || (a >= 32'h313f0000 && a < C))
        word_index = 49152 + int'(a[15:2]);
    else if (a >= PMM)
        word_index = 32768 + int'(a[15:2]);
    else if (a >= C)
        word_index = 16384 + int'(a[15:2]);
    else
        word_index = int'(a[15:2]);
endfunction

always @(posedge clk) begin
    cycle <= cycle + 1;
    phy_valid <= 0;
    if (rd && !busy) begin
        if (remaining || (burst != 1 && burst != 4)) $fatal(1, "physical read ownership/count");
        reads <= reads + 1;
        next_beat <= phy_addr;
        remaining <= int'(burst);
    end
    if (remaining && !pause_beats) begin
        index = word_index({next_beat, 3'b0});
        phy_read <= {dram[index+1], dram[index]};
        phy_valid <= 1;
        next_beat <= next_beat + 1'b1;
        remaining <= remaining - 1;
    end
    if (wr && !busy) begin
        if (remaining || burst != 1 || rd) $fatal(1, "physical write overlap/count");
        writes <= writes + 1;
        index = word_index({phy_addr, 3'b0});
        for (integer j = 0; j < 8; j++)
            if (phy_be[j]) dram[index+j/4][(j%4)*8+:8] <= phy_write[j*8+:8];
    end
end

task automatic offer(input bit w, input bit l, input [31:0] a, input [31:0] d, input [3:0] b);
    @(negedge clk);
    while (!ready) @(negedge clk);
    request = 1;
    writing = w;
    line = l;
    address = a;
    write_data = d;
    mask = b;
    @(negedge clk);
    request = 0;
    // The arbiter can move on from the live request pins after admission.
    writing = !w;
    line = !l;
    address = ~a;
    write_data = ~d;
    mask = ~b;
endtask

task automatic access(input bit w, input bit l, input [31:0] a,
                      input [31:0] d, input [3:0] b, input integer expected_reads);
    integer start_reads, start_writes, issued, seen, i;
    start_reads = reads;
    start_writes = writes;
    seen = 0;
    offer(w,l,a,d,b);
    issued = cycle;
    do begin
        if (beat_valid) begin
            i = word_index(a) + seen * 2;
            if (!l || seen >= 4 || beat_data !== {reference[i+1], reference[i]} ||
                beat_last !== (seen == 3))
                $fatal(1, "unexpected beat at %h index %0d", a, seen);
            seen++;
        end
        if (done) break;
        @(negedge clk);
    end while (1);
    if (measure) begin
        clocks += cycle-issued;
        count++;
        if (!l && expected_reads == 0) begin
            word_hits++;
            word_hit_clocks += cycle-issued;
        end else if (!l) begin
            word_misses++;
            word_miss_clocks += cycle-issued;
        end
    end
    i = word_index(a);
    if (w) begin
        for (integer j = 0; j < 4; j++)
            if (b[j]) reference[i][j*8+:8] = d[j*8+:8];
        if (dram[i] !== reference[i] || writes != start_writes+1)
            $fatal(1, "write not committed once at %h", a);
    end else if (l) begin
        if (seen != 4) $fatal(1, "short logical line");
    end else if (result !== reference[i])
        $fatal(1, "word mismatch at %h got %h expected %h", a, result, reference[i]);
    if (reads-start_reads != expected_reads)
        $fatal(1, "unexpected physical read count at %h got %0d expected %0d",
            a, reads-start_reads, expected_reads);
    completed++;
endtask

task automatic read_word(input [31:0] a, input bit hit);
    access(0,0,a,0,15,(hit && CACHE_BYTES != 0) ? 0 : 1);
endtask

task automatic read_line(input [31:0] a, input bit hit);
    access(0,1,a,0,15,(hit && CACHE_BYTES != 0) ? 0 : 1);
endtask

initial begin
    for (integer k = 0; k < 65536; k++) begin
        reference[k] = 32'h172a00e3 ^ (32'h035df928 * k);
        dram[k] = reference[k];
    end
    repeat (3) @(negedge clk);
    reset = 0;
    // Shared scalar and line entries across the audited backing regions.
    read_word(ROM+12,0);
    read_line(ROM,1);
    read_word(ROM+28,1);
    access(1,0,TRACE+4,32'hdeadbeef,15,0);
    read_word(ROM+4,1);
    read_word(32'h313f0000,0);
    read_word(32'h313f0000,0);
    read_word(32'h31810000,0);
    read_word(C+28,0);
    read_line(C,1);
    read_word(PMM+4,0);
    read_line(PMM,1);
    // Tag alias must miss. An ordered write to the other tag must keep this line.
    read_word(ROM+256,0);
    read_word(ROM+256+(CACHE_BYTES ? CACHE_BYTES : 8192),0);
    access(1,0,ROM+256,32'h0badca5e,15,0);
    read_word(ROM+256+(CACHE_BYTES ? CACHE_BYTES : 8192),1);
    read_word(ROM+256,0);
    for (integer half = 0; half < 2; half++)
        for (integer m = 0; m < 16; m++) begin
            read_word(C+64+half*4,half != 0 || m != 0);
            access(1,0,C+64+half*4,32'h84219dae ^ (m*32'h11502dbf),4'(m),0);
            read_word(C+64+half*4,m == 0);
            read_line(C+64,1);
        end
    // An interrupted fill must drain, then be fetched again. No cached prefix
    // survives the reset or gets attributed to the next request.
    offer(0,1,ROM+512,0,15);
    wait(beat_valid);
    @(negedge clk);
    pause_beats = 1;
    reset = 1;
    repeat (3) @(negedge clk);
    reset = 0;
    pause_beats = 0;
    while (!ready) begin
        @(negedge clk);
        if (done || beat_valid) $fatal(1, "stale response after reset");
    end
    read_line(ROM+512,0);
    read_word(ROM+516,1);
    if (CACHE_BYTES != 0) begin
        // Stop physical delivery after the requested word. Completion may
        // release its caller, but a writer cannot overtake the remaining fill.
        offer(0,0,ROM+768,0,15);
        wait(phy_valid);
        @(negedge clk);
        pause_beats = 1;
        wait(done);
        if (result !== reference[word_index(ROM+768)]) $fatal(1, "early word mismatch");
        @(posedge clk);
        repeat (8) begin
            @(negedge clk);
            if (ready || done || remaining != 3) $fatal(1, "early word released its fill");
        end
        pause_beats = 0;
        read_line(ROM+768,1);
    end
    // Controlled reuse probe, same accesses and DDR beat schedule in each run.
    @(negedge clk);
    measure = 1;
    count = 0;
    clocks = 0;
    begin
        integer before_reads, before_cycle;
        before_reads = reads;
        before_cycle = cycle;
        for (integer repeat_pass = 0; repeat_pass < 8; repeat_pass++)
            for (integer k = 0; k < 16; k++) begin
                read_word(ROM+4096+32*k+4,repeat_pass != 0);
                read_line(ROM+4096+32*k,1);
            end
        $display("METRIC cache_bytes=%0d stream=%0d requests=%0d DDR_reads=%0d service_clocks=%0d elapsed_clocks=%0d",
                 CACHE_BYTES, STREAM_TRANSPORT, count, reads-before_reads, clocks, cycle-before_cycle);
        $display("METRIC word_hits=%0d hit_clocks=%0d word_misses=%0d miss_clocks=%0d",
                 word_hits, word_hit_clocks, word_misses, word_miss_clocks);
    end
    // Two passes over a distinct 24 KiB window. Its overlap with the small
    // probe only evicts entries; its addresses have never been fetched.
    begin
        integer before_reads, before_cycle, expected;
        before_reads = reads;
        before_cycle = cycle;
        measure = 0;
        for (integer pass = 0; pass < 2; pass++)
            for (integer k = 0; k < 768; k++) begin
                expected = 1;
                if (pass == 1 && (CACHE_BYTES == 32768 ||
                    (CACHE_BYTES == 16384 && k >= 256 && k < 512)))
                    expected = 0;
                access(0,0,ROM+32768+32*k,0,15,expected);
            end
        while (!ready) @(negedge clk);
        $display("METRIC cache_bytes=%0d stream=%0d scan_requests=1536 scan_reads=%0d scan_clocks=%0d",
                 CACHE_BYTES, STREAM_TRANSPORT, reads-before_reads, cycle-before_cycle);
    end
    $display("PASS D2 flash cache %0d ordered transactions", completed);
    $finish;
end
initial begin
    #5000000;
    $fatal(1, "D2 cache test timeout");
end
endmodule
