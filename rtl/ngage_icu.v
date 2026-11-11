// Level-sensitive IRQ/FIQ banks. Raw status exposes every routed producer;
// current selects the lowest enabled pending source within the addressed bank.
// The legacy clear output remains for staged UEM/DMA acknowledgement only.
// Global enable is a diagnostic latch, not a verified hardware master gate.
module ngage_icu #(
    parameter PASSIVE_STORAGE = 1
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        req,
    input  wire        commit,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] din,
    input  wire [ 3:0] sel,
    input  wire [95:0] irq_pending,
    input  wire [95:0] fiq_pending,
    output reg         claim,
    output reg         bad,
    output reg  [31:0] dout,
    output wire        irq,
    output wire        fiq,
    output reg  [95:0] irq_clear,
    input  wire        timer0_rearm,
    output wire        ready
);
    reg [31:0] irq_enable[0:2], fiq_enable[0:2], global_enable;
    integer bank, slot, i;
    reg is_irq, is_fiq, is_global, is_fast;
    reg [31:0] raw_irq, raw_fiq, masked_irq, masked_fiq;
    wire [31:0] a = {addr[31:2], 2'b00};
    assign irq = |(irq_pending[31:0] & irq_enable[0]) || |(irq_pending[63:32] & irq_enable[1]) ||
        |(irq_pending[95:64] & irq_enable[2]);
    assign fiq = |(fiq_pending[31:0] & fiq_enable[0]) || |(fiq_pending[63:32] & fiq_enable[1]) ||
        |(fiq_pending[95:64] & fiq_enable[2]);

    // The six passive configuration words are independent of IRQ state.
    // Live masks/current selection keep their immediate response and timing.
    wire [ 2:0] cfg_address = {bank[1:0], a[2]};
    wire        cfg_selected = claim && !bad && is_irq && (slot == 0 || slot == 4);
    wire        cfg_write = cfg_selected && commit && we && !reset;
    wire        cfg_read = cfg_selected && !we;
    // Production UPP supplies these words from its shared store.
    // Standalone fixtures retain a local bank through PASSIVE_STORAGE=1.
    wire [31:0] passive_data;
    generate
        if (PASSIVE_STORAGE) begin : standalone_passive
            reg [5:0] cfg_valid = 0;
            reg cfg_read_pending = 0, cfg_sample_valid = 0;
            reg  [ 2:0] cfg_sample_address;
            wire [31:0] cfg_data;
            ngage_bram #(
                .AW         (3),
                .DW         (32),
                .READ_ONLY_B(1)
            ) configuration_words (
                .clk   (clk),
                .addr_a(cfg_address),
                .addr_b(cfg_address),
                .data_a(din),
                .data_b(32'b0),
                .we_a  (cfg_write),
                .we_b  (1'b0),
                .q_a   (),
                .q_b   (cfg_data)
            );
            assign passive_data = cfg_sample_valid ? cfg_data : 32'b0;
            assign ready = !cfg_read || (cfg_read_pending && cfg_sample_address == cfg_address);
            always @(posedge clk) begin
                if (reset) begin
                    cfg_valid          <= 0;
                    cfg_read_pending   <= 0;
                    cfg_sample_valid   <= 0;
                    cfg_sample_address <= 0;
                end else begin
                    if (cfg_write) cfg_valid[cfg_address] <= 1;
                    cfg_read_pending   <= cfg_read;
                    cfg_sample_address <= cfg_address;
                    cfg_sample_valid   <= cfg_read && cfg_valid[cfg_address];
                end
            end
        end else begin : shared_passive
            assign passive_data = 0;
            assign ready        = 1;
        end
    endgenerate
    // The kernel indexes the handler table with a one-based source number
    // within each bank. Select the lowest enabled pending source.
    function [5:0] irq_current;
        input [31:0] pending;
        reg [15:0] group16;
        reg [ 7:0] group8;
        reg [ 3:0] group4;
        reg [ 1:0] group2;
        reg [ 4:0] index;
        begin
            index[4]    = !(|pending[15:0]);
            group16     = index[4] ? pending[31:16] : pending[15:0];
            index[3]    = !(|group16[7:0]);
            group8      = index[3] ? group16[15:8] : group16[7:0];
            index[2]    = !(|group8[3:0]);
            group4      = index[2] ? group8[7:4] : group8[3:0];
            index[1]    = !(|group4[1:0]);
            group2      = index[1] ? group4[3:2] : group4[1:0];
            index[0]    = !group2[0];
            irq_current = (|pending) ? {1'b0, index} + 6'd1 : 6'd0;
        end
    endfunction

    always @* begin
        bank       = 0;
        slot       = 0;
        is_irq     = 0;
        is_fiq     = 0;
        is_global  = 0;
        is_fast    = 0;
        claim      = 0;
        bad        = 0;
        dout       = 0;
        raw_irq    = 0;
        raw_fiq    = 0;
        masked_irq = 0;
        masked_fiq = 0;
        if (req && (a == 32'h0c120064 || a == 32'h0c120068)) begin
            is_global = 1;
            claim     = 1;
            dout      = global_enable;
        end else if (req && a == 32'h0c120050) begin
            is_fast = 1;
            claim   = 1;
            dout    = 0;
        end else if (req && a >= 32'h0c120100 && a < 32'h0c1201c0) begin
            bank = (a - 32'h0c120100) >> 6;
            slot = a[5:0];
            if (slot == 0 || slot == 4 || slot == 8 || slot == 12 || slot == 16 || slot == 20) begin
                is_irq     = 1;
                claim      = 1;
                raw_irq    = irq_pending[bank*32+:32];
                masked_irq = raw_irq & irq_enable[bank];
                case (slot)
                    0, 4:  dout = passive_data;
                    8, 12: dout = irq_enable[bank];
                    16:    dout = raw_irq;
                    20:    dout = {26'b0, irq_current(masked_irq)};
                endcase
            end
        end else if (req && a >= 32'h0c1201c0 && a < 32'h0c120260) begin
            bank = (a - 32'h0c1201c0) >> 6;
            slot = a[5:0];
            if (slot == 8 || slot == 12 || slot == 16 || slot == 20) begin
                is_fiq     = 1;
                claim      = 1;
                raw_fiq    = fiq_pending[bank*32+:32];
                masked_fiq = raw_fiq & fiq_enable[bank];
                case (slot)
                    8, 12: dout = fiq_enable[bank];
                    16:    dout = raw_fiq;
                    20:    dout = {26'b0, irq_current(masked_fiq)};
                endcase
            end
        end
        if (claim && sel != 4'hf) bad = 1;
    end
    // Acknowledge qualification is separate from address decode: claim and
    // bad must not appear dependent on the committing CPU response path.
    always @* begin
        irq_clear = 0;
        if (commit && claim && !bad && we && is_irq && slot == 12) irq_clear[bank*32+:32] = din;
    end
    always @(posedge clk) begin
        if (reset) begin
            global_enable <= 0;
            for (i = 0; i < 3; i = i + 1) begin
                irq_enable[i] <= 0;
                fiq_enable[i] <= 0;
            end
        end else begin
            // Timer programming does not alter interrupt enable state. The
            // original boot ISR explicitly masks source 0 after stopping it.
            if (commit && claim && !bad && we) begin
                if (is_global) begin
                    if (a == 32'h0c120068) global_enable <= global_enable | din;
                    else global_enable <= global_enable & ~din;
                end else if (is_irq)
                    case (slot)
                        8:  irq_enable[bank] <= irq_enable[bank] | din;
                        12: irq_enable[bank] <= irq_enable[bank] & ~din;
                    endcase
                else if (is_fiq)
                    case (slot)
                        8:  fiq_enable[bank] <= fiq_enable[bank] | din;
                        12: fiq_enable[bank] <= fiq_enable[bank] & ~din;
                    endcase
            end
        end
    end
endmodule
