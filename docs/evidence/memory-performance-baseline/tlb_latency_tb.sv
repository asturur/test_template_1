// Directed cycle measurement for the 2026-11-11 comparison baseline.
// Present a request after a falling edge. Count rising edges through ready.
`timescale 1ns / 1ps
module test;
    reg clk = 0;
    reg reset = 1;
    reg idle = 0, inv = 0, mmu = 1, rd = 0, wr = 0;
    reg [4:0] mode_bits = 5'h13;
    reg [31:0] dac = 32'hffffffff, baddr = 32'h0a074000;
    reg [31:0] l1_descriptor = 32'h0a200001;
    reg [31:0] last_l2_address = 0;
    reg abort_l1 = 0, abort_l2 = 0, bus_error = 0, complete = 0;
    reg [31:0] descriptor = 32'h0a081ffe;
    wire fault, cacheable, bufferable;
    wire [ 7:0] external_fsr;
    wire [ 7:0] fsr;
    wire [31:0] far_address;
    reg  [31:0] current_address = 32'h80601868;
    wire busy, cyc, stb;
    wire [31:0] bus_address, physical;
    reg request_cyc = 0, request_stb = 0;
    reg [31:0] request_address = 0;
    reg ack = 0;
    reg [31:0] bus_data = 0;
    integer beats = 0;

    always #5 clk = ~clk;
    always @(posedge clk) begin
        request_cyc <= cyc;
        request_stb <= stb;
        request_address <= bus_address;
    end
    always @(negedge clk) begin
        ack = request_cyc && request_stb && !ack && !bus_error;
        bus_error = ack && (request_address < 32'h0a200000 ? abort_l1 : abort_l2);
        if (bus_error) ack = 0;
        if (ack || bus_error) begin
            beats = beats + 1;
            bus_data = request_address < 32'h0a200000 ? l1_descriptor : descriptor;
            if (request_address >= 32'h0a200000) last_l2_address = request_address;
        end
    end

    arm920_tlb dut (
        .i_clk(clk),
        .i_reset(reset),
        .i_address(current_address),
        .i_request_rd(rd),
        .i_request_wr(wr),
        .i_cpsr(mode_bits),
        .i_sr(2'b0),
        .i_dac_reg(dac),
        .i_baddr(baddr),
        .i_mmu_en(mmu),
        .i_inv(inv),
        .i_inv_mva(1'b0),
        .i_inv_address(32'b0),
        .i_lock_write(1'b0),
        .i_lock_data(32'b0),
        .i_complete(complete),
        .i_idle(idle),
        .o_busy(busy),
        .o_phy_addr(physical),
        .o_fault(fault),
        .o_cacheable(cacheable),
        .o_bufferable(bufferable),
        .o_external_fsr(external_fsr),
        .o_fsr(fsr),
        .o_far(far_address),
        .o_wb_cyc_nxt(cyc),
        .o_wb_stb_nxt(stb),
        .o_wb_adr_nxt(bus_address),
        .i_wb_dat(bus_data),
        .i_wb_ack(ack),
        .i_wb_err(bus_error)
    );

    task tick;
        begin
            @(negedge clk);
            #1;
        end
    endtask
    integer clock_count = 0;
    always @(posedge clk) clock_count = clock_count + 1;

    task measure;
        input [31:0] value;
        input [255:0] label_text;
        input integer expected_beats;
        integer begin_clock, begin_beats, elapsed;
        begin
            current_address = value;
            rd = 1;
            idle = 1;
            begin_clock = clock_count;
            begin_beats = beats;
            #1;
            while (busy && clock_count - begin_clock < 100) tick();
            elapsed = clock_count - begin_clock;
            if (busy || fault || beats - begin_beats != expected_beats)
                $fatal(1, "TLB latency fixture failed %s", label_text);
            $display("MEASURE name=%0s clocks=%0d table_reads=%0d physical=%h", label_text,
                     elapsed, beats - begin_beats, physical);
            rd = 0;
            tick();
        end
    endtask

    initial begin
        repeat (4) tick();
        reset = 0;
        measure(32'h80601868, "small_page_cold_walk", 2);
        measure(32'h8060186c, "permission_token_hit", 0);
        measure(32'h80601c00, "main_tlb_hit_other_1k", 0);
        measure(32'h80601868, "main_tlb_hit_return_1k", 0);
        mode_bits = 5'h10;
        measure(32'h80601868, "main_tlb_hit_context_change", 0);
        mode_bits = 5'h13;
        measure(32'h80602868, "small_page_new_mapping", 2);
        inv = 1;
        tick();
        inv = 0;
        l1_descriptor = 32'h0a000c0e;
        measure(32'h80800080, "section_cold_walk", 1);
        measure(32'h80800084, "section_token_hit", 0);
        mmu = 0;
        measure(32'h0a000080, "mmu_disabled_identity", 0);
        $display("PASS isolated production TLB latency measurements");
        $finish;
    end
endmodule
