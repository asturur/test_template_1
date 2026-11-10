`timescale 1ns/1ps
module test;
    reg clk = 0;
    reg reset = 1;
    reg idle = 0, hold = 0, inv = 0, mmu = 1, rd = 1, wr = 0;
    reg [4:0] mode_bits = 5'h13;
    reg [31:0] dac = 32'hffffffff, baddr = 32'h0a074000;
    reg [31:0] descriptor = 32'h0a081ffe;
    wire fault;
    wire [7:0] fsr;
    wire [31:0] far_address;
    reg [31:0] current_address = 32'h80601868;
    reg [31:0] lookup_address = 32'h80601868;
    reg [31:0] check_address = 32'h80601868;
    wire busy, cyc, stb;
    wire [31:0] bus_address, physical;
    reg request_cyc = 0, request_stb = 0;
    reg [31:0] request_address = 0;
    reg ack = 0;
    reg [31:0] bus_data = 0;
    integer beats = 0;

    always #5 clk = ~clk;
    always @(posedge clk) begin
        request_cyc <= cyc; request_stb <= stb; request_address <= bus_address;
    end
    always @(negedge clk) begin
        ack = request_cyc && request_stb && !ack;
        if (ack) begin
            beats = beats + 1;
            bus_data = request_address < 32'h0a078000 ? 32'h0a078001 : descriptor;
        end
    end

    zap_tlb #(
        .LPAGE_TLB_ENTRIES(8), .SPAGE_TLB_ENTRIES(16),
        .SECTION_TLB_ENTRIES(4), .FPAGE_TLB_ENTRIES(32)
    ) dut (
        .i_clk(clk), .i_reset(reset), .i_address(current_address),
        .i_address_check(check_address), .i_address_nxt(lookup_address),
        .i_wr_check(wr), .i_rd_check(rd), .i_request_rd(rd), .i_request_wr(wr), .i_hold(hold),
        .i_cpsr(mode_bits), .i_sr(2'b0), .i_dac_reg(dac),
        .i_baddr(baddr), .i_mmu_en(mmu), .i_inv(inv),
        .i_idle(idle), .o_busy(busy), .o_phy_addr(physical), .o_fault(fault), .o_fsr(fsr), .o_far(far_address),
        .o_wb_cyc_nxt(cyc), .o_wb_stb_nxt(stb), .o_wb_adr_nxt(bus_address),
        .i_wb_dat(bus_data), .i_wb_ack(ack), .i_wb_err(1'b0)
    );

    task tick;
        begin @(negedge clk); #1; end
    endtask
    task settle;
        integer n;
        begin
            repeat (8) tick();
            n = 0;
            while (busy && n < 200) begin tick(); n = n + 1; end
            if (busy) $fatal(1, "translation did not settle");
        end
    endtask
    task address(input [31:0] value);
        begin current_address = value; lookup_address = value; check_address = value; end
    endtask
    integer before_beats;
    initial begin
        repeat (4) tick(); reset = 0;
        repeat (6) tick(); idle = 1;
        settle();
        if (physical !== 32'h0a081868 || beats != 2 || fault) $fatal(1, "warm translation: pa=%h beats=%0d fault=%b", physical, beats, fault);
        before_beats = beats;
        current_address = current_address + 4;
        #1;
        if (busy || physical != 32'h0a08186c) $fatal(1, "adjacent instruction token/offset lost");
        current_address = current_address - 4;
        lookup_address = 0; check_address = 0;
        repeat (60) tick();
        if (beats != before_beats || busy || fault) $fatal(1, "stale lookup caused walk/fault");
        address(32'h80612868); hold = 1;
        settle(); hold = 0;
        if (beats != before_beats + 2 || physical != 32'h0a081868) $fatal(1, "held real miss repeated/lost");
        before_beats = beats;
        address(32'h80613868);
        wait (beats > before_beats); tick(); inv = 1; tick(); inv = 0;
        settle();
        if (beats < before_beats + 4 || fault) $fatal(1, "invalidation did not discard active walk");
        before_beats = beats;
        address(32'h80614868);
        wait (beats > before_beats); tick(); baddr = 32'h0a070000;
        settle();
        if (beats < before_beats + 4 || fault) $fatal(1, "TTBR change did not discard active walk");
        descriptor = 32'h0a081efe; mode_bits = 5'h10; dac = 1;
        inv = 1; tick(); inv = 0;
        settle();
        if (fault || physical != 32'h0a081868) $fatal(1, "client read permission failed");
        rd = 0; wr = 1;
        settle();
        if (!fault || fsr[3:0] != 4'hf || far_address != current_address) $fatal(1, "write permission ownership failed: fsr=%h far=%h", fsr, far_address);
        before_beats = beats;
        current_address = current_address + 32'h400;
        settle();
        if (fault || physical != 32'h0a081c68 || beats != before_beats) $fatal(1, "1KiB permission boundary reused stale fault or walked");
        rd = 1; wr = 0; settle();
        if (fault) $fatal(1, "stale write permission fault escaped into read");
        mmu = 0; settle();
        if (fault || physical != current_address) $fatal(1, "MMU disable failed");
        $display("PASS: TLB lookup ownership, exact two-beat miss, held refill, invalidation/TTBR cancellation, permission context, MMU disable");
        $finish;
    end
    initial begin #100000; $fatal(1, "timeout"); end
endmodule
