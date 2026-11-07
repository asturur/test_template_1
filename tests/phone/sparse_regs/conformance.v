`timescale 1ns/1ps
module tb;
    parameter integer ENTRIES = 64;
    reg clk = 0, reset = 1, req = 0, commit = 0, we = 0;
    reg [31:0] addr = 0, data = 0;
    reg [3:0] sel = 15;
    wire [31:0] out;
    wire full;
    reg live[0:ENTRIES-1];
    reg [31:0] keys[0:ENTRIES-1], words[0:ENTRIES-1];
    integer i, hit, vacant, seed = 47813, iteration;
    reg expected_full, collision;
    reg [31:0] expected_read, mask;
    always #5 clk = ~clk;
    ngage_sparse_regs #(.ENTRIES(ENTRIES)) dut(clk, reset, req, commit, we, addr, data, sel, out, full);
    task cycle;
        begin
            #1;
            hit = -1; vacant = -1;
            for (i = 0; i < ENTRIES; i = i + 1) begin
                if (live[i] && keys[i] == addr && hit < 0) hit = i;
                if (!live[i] && vacant < 0) vacant = i;
            end
            expected_full = req && we && hit < 0 && vacant < 0;
            if (full !== expected_full) $fatal(1, "full mismatch size=%0d addr=%h", ENTRIES, addr);
            expected_read = 0;
            if (!reset && hit >= 0) expected_read = words[hit];
            // Mixed-port same-address write/read data is unspecified in M10K.
            collision = !reset && req && commit && we && !expected_full && hit >= 0;
            @(posedge clk);
            if (reset) begin
                for (i = 0; i < ENTRIES; i = i + 1) live[i] = 0;
            end else if (req && commit && we && !expected_full) begin
                mask = {{8{sel[3]}}, {8{sel[2]}}, {8{sel[1]}}, {8{sel[0]}}};
                if (hit >= 0) words[hit] = (words[hit] & ~mask) | (data & mask);
                else begin
                    live[vacant] = 1;
                    keys[vacant] = addr;
                    words[vacant] = data & mask;
                end
            end
            #1;
            if (!collision && out !== expected_read)
                $fatal(1, "read/latency mismatch size=%0d addr=%h expected=%h got=%h", ENTRIES, addr, expected_read, out);
            // Allocation must retain the old lowest-free-slot order, never
            // consume padding, and never create duplicate entries.
            for (i = 0; i < ENTRIES; i = i + 1) begin
                if (dut.valid[i] !== live[i]) $fatal(1, "allocation mismatch slot=%0d", i);
                if (live[i] && dut.tags[i] !== keys[i]) $fatal(1, "tag mismatch slot=%0d", i);
            end
            @(negedge clk);
        end
    endtask
    initial begin
        for (i = 0; i < ENTRIES; i = i + 1) live[i] = 0;
        cycle; reset = 0;
        // Fill every physical slot using partial bytes; untouched bytes zero.
        req = 1; commit = 1; we = 1; sel = 1;
        for (iteration = 0; iteration < ENTRIES; iteration = iteration + 1) begin
            addr = 'h0d000220 + iteration * 'h10000;
            data = 'h12345680 + iteration;
            cycle;
        end
        // Refuse a new address but allow updates to all existing entries at full.
        addr = 'hdead0000; data = 'hffffffff; sel = 15; cycle;
        for (iteration = 0; iteration < ENTRIES; iteration = iteration + 1) begin
            addr = 'h0d000220 + iteration * 'h10000;
            we = 1; sel = 10; data = 'hffeeddcc; cycle;
            we = 0; cycle;
        end
        for (iteration = 0; iteration < 4000; iteration = iteration + 1) begin
            addr = 'h0d000220 + (iteration % (ENTRIES + 3)) * 'h10000;
            if (iteration % 13 == 0) addr = addr + 1; // Full byte-address identity.
            req = ($random(seed) & 3) != 0;
            commit = $random(seed) & 1;
            we = $random(seed) & 1;
            data = $random(seed); sel = $random(seed);
            reset = iteration % 211 == 210;
            cycle;
        end
        $display("PASS sparse CAM conformance ENTRIES=%0d: capacity, updates, masks, allocation, latency, reset", ENTRIES);
        $finish;
    end
endmodule
