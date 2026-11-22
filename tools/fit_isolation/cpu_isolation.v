// SPDX-License-Identifier: GPL-3.0-or-later
// Fit-only CPU wrapper. Keep the physical production PLL and its instance path.
module ngage_cpu_isolation (
    input  wire       FPGA_CLK2_50,
    input  wire [3:0] SW,
    output wire       LED_USER,
    output wire       LED_POWER
);
    ngage_cpu_isolation_emu emu (
        .ref_clock(FPGA_CLK2_50),
        .switches (SW),
        .running  (LED_POWER),
        .progress (LED_USER)
    );
endmodule

module ngage_cpu_isolation_emu (
    input  wire       ref_clock,
    input  wire [3:0] switches,
    output wire       running,
    output wire       progress
);
    wire clk, locked;
    pll pll (
        .refclk  (ref_clock),
        .rst     (1'b0),
        .outclk_0(clk),
        .outclk_1(),
        .locked  (locked)
    );

    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [4:0] sync_first = 5'b10001, sync_second = 5'b10001;
    (* dont_retime *) reg reset = 1'b1;
    always @(posedge clk) begin
        sync_first  <= {!locked, switches};
        sync_second <= sync_first;
        reset       <= sync_second[4] || sync_second[0];
    end
    assign running = !reset;

    wire line_ready, line_reject, line_valid, line_wide, line_last, line_guaranteed;
    wire [63:0] line_data;
    wire line_req, wb_cyc, wb_stb, wb_code, wb_lock, wb_write, wb_block;
    wire [31:0] line_address, wb_address, wb_data, wb_reply;
    wire [127:0] wb_block_data;
    wire [3:0] wb_mask;
    wire wb_ack, wb_error, irq, fiq;
    // Readout registers deliberately do not feed a wide reduction network.
    // The ports otherwise unobserved by the shipping build remain open.
    (* noprune, preserve, dont_retime *) reg [234:0] request_sample;
    reg [5:0] completed = 0;
    always @(posedge clk) begin
        request_sample <= {line_req, line_address, wb_cyc, wb_stb, wb_code, wb_lock,
                           wb_write, wb_block, wb_address, wb_data, wb_block_data, wb_mask};
        if (reset) completed <= 0;
        else if (wb_ack || line_last || wb_error) completed <= completed + 1'b1;
    end
    assign progress = completed[5];

    ngage_cpu #(
        .LINE_REFILL            (1),
        .EXPLICIT_LINE_GUARANTEE(1),
        .REGISTERED_SCALAR_PEER (1)
    ) cpu (
        .clk                (clk),
        .reset              (reset),
        .irq                (irq),
        .fiq                (fiq),
        .line_req           (line_req),
        .line_addr          (line_address),
        .line_ready         (line_ready),
        .line_reject        (line_reject),
        .line_valid         (line_valid),
        .line_data          (line_data),
        .line_wide          (line_wide),
        .line_last          (line_last),
        .line_error         (1'b0),
        .line_no_late_error (line_guaranteed),
        .wb_cyc             (wb_cyc),
        .wb_stb             (wb_stb),
        .wb_code            (wb_code),
        .wb_lock            (wb_lock),
        .wb_address         (wb_address),
        .wb_write           (wb_write),
        .wb_write_data      (wb_data),
        .wb_write_block     (wb_block),
        .wb_block_data      (wb_block_data),
        .wb_byte_enable     (wb_mask),
        .wb_cycle_type      (),
        .wb_burst_type      (),
        .wb_ack             (wb_ack),
        .wb_error           (wb_error),
        .wb_read_data       (wb_reply),
        .debug_pc           (),
        .debug_cpsr         (),
        .debug_instruction  (),
        .debug_fetch        ()
    );

    ngage_cpu_isolation_peer peer (
        .clk             (clk),
        .reset           (reset),
        .traffic         (sync_second[3:1]),
        .irq             (irq),
        .fiq             (fiq),
        .line_req        (line_req),
        .line_address    (line_address),
        .line_ready      (line_ready),
        .line_reject     (line_reject),
        .line_valid      (line_valid),
        .line_last       (line_last),
        .line_wide       (line_wide),
        .line_guaranteed (line_guaranteed),
        .line_data       (line_data),
        .wb_request      (wb_cyc && wb_stb),
        .wb_address      (wb_address),
        .wb_write        (wb_write),
        .wb_data         (wb_data),
        .wb_mask         (wb_mask),
        .wb_ack          (wb_ack),
        .wb_error        (wb_error),
        .wb_reply        (wb_reply)
    );
endmodule

module ngage_cpu_isolation_peer (
    input  wire        clk,
    input  wire        reset,
    input  wire [ 2:0] traffic,
    (* dont_retime *) output reg         irq,
    (* dont_retime *) output reg         fiq,
    input  wire        line_req,
    input  wire [31:0] line_address,
    (* dont_retime *) output reg         line_ready,
    (* dont_retime *) output reg         line_reject,
    (* dont_retime *) output reg         line_valid,
    (* dont_retime *) output reg         line_last,
    (* dont_retime *) output reg         line_wide,
    (* dont_retime *) output reg         line_guaranteed,
    (* dont_retime *) output reg  [63:0] line_data,
    input  wire        wb_request,
    input  wire [31:0] wb_address,
    input  wire        wb_write,
    input  wire [31:0] wb_data,
    input  wire [ 3:0] wb_mask,
    (* dont_retime *) output reg         wb_ack,
    (* dont_retime *) output reg         wb_error,
    (* dont_retime *) output reg  [31:0] wb_reply
);
    reg [31:0] entropy_low, entropy_high;
    reg [31:0] scratch_word;
    reg [31:0] refill_addr;
    reg        refill_live;
    reg [ 3:0] pieces;

    function [31:0] mapped_word;
        input [31:0] address;
        input [31:0] saved_word;
        begin
            // CP15 TTBR/DACR, identity sections, I-cache and MMU enable.
            // The loop then exercises RAM word/byte writes and SWP ownership.
            case (address)
                32'h00: mapped_word = 32'he59f001c; // ldr r0,[pc,#28]
                32'h04: mapped_word = 32'hee020f10; // mcr p15,0,r0,c2,c0,0
                32'h08: mapped_word = 32'he3a00003; // mov r0,#3
                32'h0c: mapped_word = 32'hee030f10; // mcr p15,0,r0,c3,c0,0
                32'h10: mapped_word = 32'hee110f10; // mrc p15,0,r0,c1,c0,0
                32'h14: mapped_word = 32'he3800a01; // orr r0,r0,#0x1000
                32'h18: mapped_word = 32'he3800001; // orr r0,r0,#1
                32'h1c: mapped_word = 32'hee010f10; // mcr p15,0,r0,c1,c0,0
                32'h20: mapped_word = 32'hea000006; // b 0x40
                32'h24: mapped_word = 32'h0a004000;
                32'h40: mapped_word = 32'he59f0018; // ldr r0,[pc,#24]
                32'h44: mapped_word = 32'he3a01055; // mov r1,#0x55
                32'h48: mapped_word = 32'he5801000; // str r1,[r0]
                32'h4c: mapped_word = 32'he5902000; // ldr r2,[r0]
                32'h50: mapped_word = 32'he2823001; // add r3,r2,#1
                32'h54: mapped_word = 32'he1004093; // swp r4,r3,[r0]
                32'h58: mapped_word = 32'he5c03001; // strb r3,[r0,#1]
                32'h5c: mapped_word = 32'heafffff7; // b 0x40
                32'h60: mapped_word = 32'h0a000100;
                32'h0a000100: mapped_word = saved_word;
                default: mapped_word = address[31:14] == 18'h02801 ?
                    {address[13:2], 20'h00c0e} : 32'he1a00000;
            endcase
        end
    endfunction
    wire [31:0] word_low = mapped_word({refill_addr[31:2], 2'b00}, scratch_word);
    wire [31:0] word_high = mapped_word(refill_addr + 32'd4, scratch_word);
    integer lane;
    always @(posedge clk) begin
        wb_ack      <= 0;
        wb_error    <= 0;
        line_reject <= 0;
        line_valid  <= 0;
        line_last   <= 0;
        if (reset) begin
            entropy_low     <= 32'h3ae59fb7;
            entropy_high    <= 32'h1cd793e5;
            line_ready      <= 0;
            line_guaranteed <= 0;
            line_wide       <= 0;
            refill_live     <= 0;
            refill_addr     <= 0;
            pieces          <= 0;
            irq             <= 0;
            fiq             <= 0;
            scratch_word    <= 0;
            wb_reply        <= 0;
            line_data       <= 0;
        end else begin
            entropy_low  <= {entropy_low[30:0], entropy_low[31] ^ entropy_low[21] ^ entropy_low[1] ^ entropy_low[0]};
            entropy_high <= {entropy_high[30:0], entropy_high[31] ^ entropy_high[21] ^ entropy_high[1] ^ entropy_high[0]};
            irq <= traffic[0] && (&entropy_low[7:0]);
            fiq <= traffic[0] && (&entropy_high[7:0]);

            if (wb_request && !wb_ack && !wb_error) begin
                wb_error <= traffic[0] && entropy_high[0] && entropy_high[4];
                wb_ack   <= !(traffic[0] && entropy_high[0] && entropy_high[4]);
                wb_reply <= traffic[0] ? entropy_low : mapped_word(wb_address, scratch_word);
                if (wb_write && wb_address[31:2] == 30'h02800040)
                    for (lane = 0; lane < 4; lane = lane + 1)
                        if (wb_mask[lane]) scratch_word[lane*8+:8] <= wb_data[lane*8+:8];
            end
            if (line_req && line_ready) begin
                line_ready  <= 0;
                line_reject <= traffic[1];
                refill_live <= !traffic[1];
                refill_addr <= line_address;
                line_wide   <= !traffic[2];
                pieces      <= 0;
            end else if (refill_live) begin
                line_valid  <= 1;
                line_last   <= pieces == (line_wide ? 4'd3 : 4'd15);
                if (pieces == (line_wide ? 4'd3 : 4'd15)) refill_live <= 0;
                pieces      <= pieces + 1'b1;
                refill_addr <= refill_addr + (line_wide ? 32'd8 : 32'd2);
                if (traffic[0]) line_data <= {entropy_high, entropy_low};
                else if (line_wide) line_data <= {word_high, word_low};
                else line_data <= {48'd0, refill_addr[1] ? word_low[31:16] : word_low[15:0]};
            end else begin
                line_ready      <= 1;
                line_guaranteed <= !traffic[1] && !traffic[0];
            end
        end
    end
endmodule
