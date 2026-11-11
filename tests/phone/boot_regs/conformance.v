`timescale 1ns/1ps
module tb;
    reg clk = 0, reset = 1, req = 0, commit = 0, we = 0;
    reg [31:0] addr = 0, din = 0;
    reg [3:0] sel = 0;
    wire claim, bad, ready;
    wire [31:0] dout;
    reg [31:0] address_map[0:55], expected[0:55];
    reg [3:0] written[0:55];
    integer i, j, slot, seed = 27383, iteration;
    reg [31:0] mask, wanted;
    reg wanted_claim, wanted_bad;
    always #5 clk = ~clk;
    ngage_boot_regs dut(clk, reset, req, commit, we, addr, din, sel, claim, bad, dout, ready);
    task check;
        begin
            slot = -1;
            for (j = 0; j < 56; j = j + 1)
                if ({addr[31:2], 2'b0} == address_map[j]) slot = j;
            mask = {{8{sel[3]}}, {8{sel[2]}}, {8{sel[1]}}, {8{sel[0]}}};
            wanted_claim = req && slot >= 0;
            wanted_bad = 0;
            wanted = 0;
            if (wanted_claim) begin
                wanted = slot < 11 ? expected[slot] & mask : expected[slot];
                wanted_bad = !we && ((written[slot] & sel) != sel);
            end
            if (claim !== wanted_claim || bad !== wanted_bad || ((!we && ready || !req) && dout !== wanted))
                $fatal(1, "boot conformance addr=%h sel=%h req=%b we=%b got=%b/%b/%h expected=%b/%b/%h",
                       addr, sel, req, we, claim, bad, dout, wanted_claim, wanted_bad, wanted);
        end
    endtask
    task cycle;
        begin
            #1; check;
            @(posedge clk);
            if (reset) begin
                for (i = 0; i < 56; i = i + 1) begin
                    expected[i] = 0;
                    written[i] = i == 6 ? 15 : 0;
                end
            end else if (wanted_claim && commit && we) begin
                expected[slot] = (expected[slot] & ~mask) | (din & mask);
                written[slot] = written[slot] | sel;
            end
            #1; check;
            @(negedge clk);
        end
    endtask
    initial begin
        address_map[0] = 'h08000000; address_map[1] = 'h08000004;
        address_map[2] = 'h08000008; address_map[3] = 'h08000010;
        address_map[4] = 'h08000014; address_map[5] = 'h08000018;
        address_map[6] = 'h08000040; address_map[7] = 'h0c120014;
        address_map[8] = 'h0c120018; address_map[9] = 'h0c120034;
        address_map[10] = 'h0c120038;
        for (i = 11; i < 56; i = i + 1) address_map[i] = 'h0c004748 + (i - 11) * 4;
        @(posedge clk); #1; @(negedge clk);
        for (i = 0; i < 56; i = i + 1) begin expected[i] = 0; written[i] = i == 6 ? 15 : 0; end
        reset = 0;
        for (iteration = 0; iteration < 12000; iteration = iteration + 1) begin
            // Visit every byte mask and latch, unaligned aliases, nearby holes,
            // reads before writes, withheld commits, idle cycles and reset.
            addr = address_map[iteration % 56] | (iteration % 4);
            if (iteration % 7 == 0) addr = 'h0c004700 + (iteration % 80) * 4;
            if (iteration % 17 == 0) addr = 'h0800000c;
            req = ($random(seed) & 7) != 0;
            commit = $random(seed) & 1;
            we = $random(seed) & 1;
            sel = $random(seed);
            din = $random(seed);
            reset = iteration % 997 == 996;
            cycle;
        end
        // Exercise completed synchronous reads, not only canceled random requests.
        reset = 0; req = 1; we = 0; commit = 0; sel = 15;
        for (iteration = 0; iteration < 56; iteration = iteration + 1) begin
            addr = address_map[iteration];
            cycle;
            cycle;
            if (!ready) $fatal(1, "boot RAM read did not become ready");
        end
        $display("PASS boot register conformance: 12000 cycles, all latches, masks, holes and resets");
        $finish;
    end
endmodule
