// SPDX-License-Identifier: GPL-3.0-or-later
// N-Gage CPU integration boundary. Board clocks, SDRAM and peripherals
// belong outside this module. The reference build uses patched ZAP ARM920T.
module ngage_cpu #(
    parameter LINE_REFILL             = 0,
    parameter EXPLICIT_LINE_GUARANTEE = 0,
    parameter REGISTERED_SCALAR_PEER  = 0
) (

    output wire        line_req,
    output wire [31:0] line_addr,
    input  wire        line_ready,
    input  wire        line_reject,
    input  wire        line_valid,
    input  wire [63:0] line_data,
    input  wire        line_wide,
    input  wire        line_last,
    input  wire        line_error,
    // Missing guarantee holds fetched instruction words until line completion.
    input  wire        line_no_late_error,

    input  logic         clk,
    input  logic         reset,
    input  logic         irq,
    input  logic         fiq,
    output logic         wb_cyc,
    output logic         wb_lock,
    output wire          wb_code,
    output logic         wb_stb,
    output logic [ 31:0] wb_address,
    output logic         wb_write,
    output logic [ 31:0] wb_write_data,
    output wire          wb_write_block,
    output wire  [127:0] wb_block_data,
    output logic [  3:0] wb_byte_enable,
    output logic [  2:0] wb_cycle_type,
    output logic [  1:0] wb_burst_type,
    input  logic         wb_ack,
    input  logic         wb_error,
    input  logic [ 31:0] wb_read_data,
    output wire  [ 31:0] debug_pc,
    output wire  [ 31:0] debug_cpsr,
    output wire  [ 31:0] debug_instruction,
    output wire          debug_fetch
);
`ifdef NGAGE_ARM9V2
    wire [31:0] donor_pc, donor_cpsr, donor_instruction;
    wire donor_fetch, donor_line_candidate;
    wire donor_cyc, donor_lock, donor_ack, donor_error, donor_no_late_error;
    wire [31:0] donor_read_data;
    assign wb_stb = wb_cyc;

    ngage_arm9v2_refill #(
        .ENABLE                (LINE_REFILL),
        .REGISTERED_SCALAR_PEER(REGISTERED_SCALAR_PEER)
    ) refill (
        .clk               (clk),
        .reset             (reset),
        .cpu_cyc           (donor_cyc),
        .cpu_lock          (donor_lock),
        .cpu_line_candidate(donor_line_candidate),
        .cpu_address       (wb_address),
        .cpu_write         (wb_write),
        .cpu_sel           (wb_byte_enable),
        .cpu_cti           (wb_cycle_type),
        .cpu_bte           (wb_burst_type),
        .cpu_ack           (donor_ack),
        .cpu_error         (donor_error),
        .cpu_no_late_error (donor_no_late_error),
        .line_no_late_error(EXPLICIT_LINE_GUARANTEE && line_no_late_error),
        .cpu_data          (donor_read_data),
        .wb_cyc            (wb_cyc),
        .wb_lock           (wb_lock),
        .wb_ack            (wb_ack),
        .wb_error          (wb_error),
        .wb_data           (wb_read_data),
        .line_req          (line_req),
        .line_addr         (line_addr),
        .line_ready        (line_ready),
        .line_reject       (line_reject),
        .line_valid        (line_valid),
        .line_data         (line_data),
        .line_wide         (line_wide),
        .line_last         (line_last),
        .line_error        (line_error)
    );

`ifndef NGAGE_NO_CPU_DEBUG
    assign debug_pc          = donor_pc;
    assign debug_cpsr        = donor_cpsr;
    assign debug_instruction = donor_instruction;
    assign debug_fetch       = donor_fetch;
`endif

    ngage2_arm925t u_arm925t (
        .clk               (clk),
        .reset             (reset),
        .irq               (irq),
        .fiq               (fiq),
        .bus_req           (donor_cyc),
        .bus_lock          (donor_lock),
        .bus_line_candidate(donor_line_candidate),
        .bus_code          (wb_code),
        .bus_addr          (wb_address),
        .bus_we            (wb_write),
        .bus_wdata         (wb_write_data),
`ifdef NGAGE_BLOCK_WRITEBACK
        .block_enable      (1'b1),
        .bus_write_block   (wb_write_block),
        .bus_block_data    (wb_block_data),
`endif
        .bus_be            (wb_byte_enable),
        .bus_cti           (wb_cycle_type),
        .bus_bte           (wb_burst_type),
        .bus_burst         (),
        .bus_ack           (donor_ack),
        .bus_err           (donor_error),
        .bus_rdata         (donor_read_data),
        .bus_no_late_error (donor_no_late_error),
        .dbg_pc            (donor_pc),
        .dbg_wb_cpsr       (donor_cpsr),
        .dbg_instruction   (donor_instruction),
        .dbg_fetch_valid   (donor_fetch)
    );
`else
    zap_top #(
        .LINE_REFILL    (LINE_REFILL),
        .CP15_L4_DEFAULT(1'b1),
        .ONLY_CORE      (1'b0),
        .RESET_VECTOR   (32'h00000000),
        .DATA_CACHE_SIZE(16384),
        .CODE_CACHE_SIZE(16384),
        .DATA_CACHE_LINE(32),
        .CODE_CACHE_LINE(32)
    ) u_zap (
        .line_req   (line_req),
        .line_addr  (line_addr),
        .line_ready (line_ready),
        .line_reject(line_reject),
        .line_valid (line_valid),
        .line_data  (line_data),
        .line_wide  (line_wide),
        .line_last  (line_last),
        .line_error (line_error),

`ifndef NGAGE_NO_CPU_DEBUG
        .o_debug_pc         (debug_pc),
        .o_debug_cpsr       (debug_cpsr),
        .o_debug_instruction(debug_instruction),
        .o_debug_fetch      (debug_fetch),
`endif
        .i_clk              (clk),
        .i_reset            (reset),
        .i_irq              (irq),
        .i_fiq              (fiq),
        .o_wb_lock          (wb_lock),
        .o_wb_code          (wb_code),
        .o_wb_cyc           (wb_cyc),
        .o_wb_stb           (wb_stb),
        .o_wb_adr           (wb_address),
        .o_wb_we            (wb_write),
        .o_wb_dat           (wb_write_data),
        .o_wb_sel           (wb_byte_enable),
        .o_wb_cti           (wb_cycle_type),
        .o_wb_bte           (wb_burst_type),
        .i_wb_ack           (wb_ack),
        .i_wb_dat           (wb_read_data),
        .i_wb_err           (wb_error)
    );
`endif
`ifndef NGAGE_BLOCK_WRITEBACK
    assign wb_write_block = 1'b0;
    assign wb_block_data  = 128'b0;
`endif
`ifdef NGAGE_NO_CPU_DEBUG
    assign debug_pc          = 0;
    assign debug_cpsr        = 0;
    assign debug_instruction = 0;
    assign debug_fetch       = 0;
`endif
endmodule

// Convert a linear eight-word donor read burst to one board line request.
// The board can send 16-bit SDRAM or 64-bit DDR beats without backpressure.
// Deliver each registered word in order while the rest of the line arrives.
module ngage_arm9v2_refill #(
    parameter ENABLE                 = 0,
    parameter REGISTERED_SCALAR_PEER = 0
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        cpu_cyc,
    input  wire        cpu_lock,
    input  wire        cpu_line_candidate,
    input  wire [31:0] cpu_address,
    input  wire        cpu_write,
    input  wire [ 3:0] cpu_sel,
    input  wire [ 2:0] cpu_cti,
    input  wire [ 1:0] cpu_bte,
    output wire        cpu_ack,
    output wire        cpu_error,
    output wire        cpu_no_late_error,
    input  wire        line_no_late_error,
    output wire [31:0] cpu_data,
    output wire        wb_cyc,
    output wire        wb_lock,
    input  wire        wb_ack,
    input  wire        wb_error,
    input  wire [31:0] wb_data,
    output wire        line_req,
    output wire [31:0] line_addr,
    input  wire        line_ready,
    input  wire        line_reject,
    input  wire        line_valid,
    input  wire [63:0] line_data,
    input  wire        line_wide,
    input  wire        line_last,
    input  wire        line_error
);
    localparam       IDLE  = 2'd0, LINE = 2'd1, SCALAR = 2'd2;
    localparam [2:0] BURST = 3'b010, END_BEAT = 3'b111;
    reg [1:0] state;
    reg [4:0] received;
    reg [2:0] consumed;
    reg failed, guaranteed;
    reg [15:0] low_half;
    reg [31:0] words       [0:7];
    (* dont_retime *)reg [ 7:0] ready_words;

    wire burst = cpu_cti == BURST;
    assign line_req  = ENABLE && !reset && state == IDLE && cpu_cyc && !cpu_lock &&
                       cpu_line_candidate;
    assign line_addr = cpu_address;
    assign wb_cyc = !reset && cpu_cyc && state != LINE && !line_req;
    // A younger SWP cannot reach the bus before this older refill retires.
    // Its lock must not prevent SDRAM from accepting the owned line request.
    assign wb_lock = !reset && cpu_lock && state != LINE;
    // The UPP route returns a scalar reply only after capturing its owner.
    // Remember that we offered this beat. A dropped donor CYC masks the
    // reply immediately, and a later request must establish its own owner.
    // A same-edge responder still uses the current scalar offer.
    (* dont_retime *)reg  scalar_offered;
    wire scalar_reply = REGISTERED_SCALAR_PEER ? !reset && cpu_cyc && scalar_offered : wb_cyc;
    always @(posedge clk) scalar_offered <= wb_cyc && !(scalar_offered && (wb_ack || wb_error));

    // Thermometer-coded occupancy. Bit zero is the registered nonempty
    // flag, updated on the same edge as word assembly and consumption.
    wire line_beat = line_valid && received < 16;
    wire push_two = line_beat && line_wide;
    wire push_one = line_beat && !line_wide && received[0];
    wire pop_word = cpu_cyc && ready_words[0];
    always @(posedge clk) begin
        if (reset || state != LINE) ready_words <= 0;
        else if (!failed)
            case ({
                push_two, push_one, pop_word
            })
                3'b001:         ready_words <= {1'b0, ready_words[7:1]};
                3'b010, 3'b101: ready_words <= {ready_words[6:0], 1'b1};
                3'b100:         ready_words <= {ready_words[5:0], 2'b11};
                default:        ;
            endcase
    end

    assign cpu_ack = state == LINE ? cpu_cyc && !failed && ready_words[0] : scalar_reply && wb_ack;
    assign cpu_error = state == LINE ? cpu_cyc && failed : scalar_reply && wb_error;
    // A scalar fallback never grants the promise, including a line rejected
    // before its first beat. The cache samples this alongside the first ACK.
    assign cpu_no_late_error = state == LINE && guaranteed && cpu_ack;
    assign cpu_data = state == LINE ? words[consumed] : wb_data;

    always @(posedge clk) begin
        if (reset) begin
            state      <= IDLE;
            received   <= 0;
            consumed   <= 0;
            failed     <= 0;
            guaranteed <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (line_req && line_ready) begin
                        state      <= LINE;
                        received   <= 0;
                        consumed   <= 0;
                        failed     <= 0;
                        guaranteed <= line_no_late_error;
                    end else if (wb_cyc && burst) state <= SCALAR;
                end
                LINE: begin
                    if (line_reject) state <= SCALAR;
                    if (line_valid && received < 16) begin
                        received <= received + (line_wide ? 5'd4 : 5'd1);
                        if (line_error) failed <= 1;
                    end
                    if (cpu_ack || cpu_error) begin
                        consumed <= consumed + 1'b1;
                        if (consumed == 7) state <= IDLE;
                    end
                end
                SCALAR:  if (scalar_reply && !burst && (wb_ack || wb_error)) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end

    always @(posedge clk)
        if (state == LINE && line_valid && !line_wide && !received[0])
            low_half <= line_data[15:0];

    genvar slot;
    generate
        for (slot = 0; slot < 8; slot = slot + 1) begin : line_word
            always @(posedge clk) begin
                if (state == LINE && line_valid && received < 16) begin
                    if (line_wide && received[3:2] == slot >> 1)
                        words[slot] <= line_data[(slot%2)*32+:32];
                    else if (!line_wide && received[0] && received[3:1] == slot)
                        words[slot] <= {line_data[15:0], low_half};
                end
            end
        end
    endgenerate

    // synthesis translate_off
    wire line_target = cpu_address[31:24] == 8'h0a || cpu_address < 32'h007f0000 ||
                       (cpu_address >= 32'h02000000 && cpu_address < 32'h02400000) ||
                       (cpu_address >= 32'h04000000 && cpu_address < 32'h04800000);
    wire reference_candidate = !cpu_write && cpu_sel == 4'hf && burst && cpu_bte == 0 &&
                               cpu_address[4:0] == 0 && line_target;
    always @(posedge clk)
        if (!reset && cpu_cyc && cpu_line_candidate !== reference_candidate)
            $fatal(1, "Refill classifier disagrees for active packet at %h", cpu_address);

    always @(posedge clk)
        if (!reset && state == LINE) begin
            if (!failed && ready_words[0] !== (received[4:1] > {1'b0, consumed}))
                $fatal(1, "Refill word occupancy disagrees with its counters");
            if (!cpu_cyc || cpu_write || cpu_address[4:0] != {consumed, 2'b00} ||
            cpu_cti != (consumed == 7 ? END_BEAT : BURST))
                $fatal(1, "Donor changed the owned line burst");
            if (line_valid && line_error && guaranteed)
                $fatal(1, "Guaranteed line returned an error");
            if (line_reject && received != 0) $fatal(1, "Line rejected after data");
            if (line_valid && (received >= 16 || (line_wide && received[1:0] != 0) ||
            (!line_error && line_last != (received + (line_wide ? 5'd4 : 5'd1) == 16))))
                $fatal(1, "Bad board line framing");
        end
    // synthesis translate_on
endmodule
