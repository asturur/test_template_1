// Boot-controller latches and executable scratch. A byte is readable only
// after the firmware wrote it, except the documented zero-reset 0x08000040.
module ngage_boot_regs (
    input  wire        clk,
    input  wire        reset,
    input  wire        req,
    input  wire        commit,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] din,
    input  wire [ 3:0] sel,
    output reg         claim,
    output reg         bad,
    output reg  [31:0] dout,
    output wire        ready
);
    reg [3:0] valid[0:10], scratch_valid[0:44];
    wire [31:0] a = {addr[31:2], 2'b00};
    wire [31:0] mask = {{8{sel[3]}}, {8{sel[2]}}, {8{sel[1]}}, {8{sel[0]}}};
    wire        scratch_hit = a >= 32'h0c004748 && a <= 32'h0c0047f8;
    wire [31:0] scratch_q;
    reg  [ 3:0] zero_payload_valid;
    wire [63:0] selected, missing;
    wire [5:0] row_tree[0:126];
    wire [3:0] bytes_tree[0:126];
    wire [5:0] storage_index = row_tree[0];
    wire [3:0] stored_bytes = bytes_tree[0];
    wire [31:0] storage_mask = {
        {8{stored_bytes[3]}}, {8{stored_bytes[2]}}, {8{stored_bytes[1]}}, {8{stored_bytes[0]}}
    };
    reg read_valid;
    reg [5:0] read_address;
    // Both groups share the same one-clock RAM read contract. Fault validity
    // stays a parallel per-address reduction; every write remains immediate.
    assign ready = !reset && (!req || we || !(|selected) ||
        (read_valid && read_address == storage_index));
    always @(posedge clk) begin
        if (reset || !req || we) read_valid <= 0;
        else begin
            read_valid   <= 1;
            read_address <= storage_index;
        end
    end
    ngage_bram_be #(
        .AW(6)
    ) scratch_ram (
        .clk  (clk),
        .raddr(storage_index),
        .rdata(scratch_q),
        .waddr(storage_index),
        .we   ((!reset && req && commit && we && (|selected)) ? sel : 4'b0),
        .wdata(din)
    );

    // Constant address comparisons select each latch directly. Encoding an
    // index and then muxing the validity arrays put a long read-fault path
    // onto shared Wishbone ACK, including unrelated device transactions.
    function [31:0] boot_address;
        input integer slot;
        begin
            case (slot)
                0:       boot_address = 32'h08000000;
                1:       boot_address = 32'h08000004;
                2:       boot_address = 32'h08000008;
                3:       boot_address = 32'h08000010;
                4:       boot_address = 32'h08000014;
                5:       boot_address = 32'h08000018;
                6:       boot_address = 32'h08000040;
                7:       boot_address = 32'h0c120014;
                8:       boot_address = 32'h0c120018;
                9:       boot_address = 32'h0c120034;
                default: boot_address = 32'h0c120038;
            endcase
        end
    endfunction
    genvar slot;
    generate
        for (slot = 0; slot < 11; slot = slot + 1) begin : boot_latches
            assign selected[slot] = a == boot_address(slot);
            assign missing[slot] = selected[slot] && ((valid[slot] & sel) != sel);
            assign row_tree[63+slot] = selected[slot] ? 6'd45 + slot : 6'd0;
            assign bytes_tree[63+slot] = selected[slot] ?
                (slot == 6 ? zero_payload_valid : valid[slot]) : 4'b0;
            always @(posedge clk) begin
                if (reset) begin
                    valid[slot] <= slot == 6 ? 4'hf : 0;
                end else if (req && commit && we && selected[slot]) begin
                    valid[slot] <= valid[slot] | sel;
                end
            end
        end
        for (slot = 0; slot < 45; slot = slot + 1) begin : scratch_latches
            assign selected[11+slot]   = a == (32'h0c004748 + slot * 4);
            assign missing[11+slot]    = selected[11+slot] && ((scratch_valid[slot] & sel) != sel);
            assign row_tree[74+slot]   = selected[11+slot] ? slot : 6'd0;
            assign bytes_tree[74+slot] = selected[11+slot] ? scratch_valid[slot] : 4'b0;
            always @(posedge clk) begin
                if (reset) begin
                    scratch_valid[slot] <= 0;
                end else if (req && commit && we && selected[11+slot]) begin
                    scratch_valid[slot] <= scratch_valid[slot] | sel;
                end
            end
        end
        for (slot = 56; slot < 64; slot = slot + 1) begin : unused_leaves
            assign selected[slot]      = 0;
            assign missing[slot]       = 0;
            assign row_tree[63+slot]   = 0;
            assign bytes_tree[63+slot] = 0;
        end
        for (slot = 0; slot < 63; slot = slot + 1) begin : data_nodes
            assign row_tree[slot]   = row_tree[2*slot+1] | row_tree[2*slot+2];
            assign bytes_tree[slot] = bytes_tree[2*slot+1] | bytes_tree[2*slot+2];
        end
    endgenerate
    //0x08000040 is readable as zero immediately after reset even though its
    // physical RAM row retains old data. Track stored bytes separately there.
    always @(posedge clk) begin
        if (reset) zero_payload_valid <= 0;
        else if (req && commit && we && selected[6]) zero_payload_valid <= zero_payload_valid | sel;
    end
    always @* begin
        claim = req && (|selected);
        bad   = claim && !we && (|missing);
        // Unwritten bytes remain zero after warm reset even though the RAM
        // itself is not reset. Scratch reads expose all valid stored bytes.
        dout  = !req ? 32'b0 : scratch_q & storage_mask & (scratch_hit ? 32'hffffffff : mask);
    end
endmodule
