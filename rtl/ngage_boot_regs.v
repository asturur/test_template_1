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
    reg [31:0] values[0:10];
    reg [3:0] valid[0:10], scratch_valid[0:44];
    wire [31:0] a = {addr[31:2], 2'b00};
    wire [31:0] mask = {{8{sel[3]}}, {8{sel[2]}}, {8{sel[1]}}, {8{sel[0]}}};
    wire scratch_hit = a >= 32'h0c004748 && a <= 32'h0c0047f8;
    wire [5:0] scratch_index = a[7:2] - 6'h12;
    wire [31:0] scratch_q;
    wire [3:0] scratch_bytes = scratch_hit ? scratch_valid[scratch_index] : 4'b0;
    wire [31:0] scratch_mask = {
        {8{scratch_bytes[3]}}, {8{scratch_bytes[2]}}, {8{scratch_bytes[1]}}, {8{scratch_bytes[0]}}
    };
    reg read_valid;
    reg [31:0] read_address;
    // Only scratch reads need the synchronous RAM edge. Fixed boot latches
    // and all writes retain their immediate admission contract.
    assign ready = !reset && (!req || we || !scratch_hit || (read_valid && read_address == a));
    always @(posedge clk) begin
        if (reset || !req || we) read_valid <= 0;
        else begin
            read_valid   <= 1;
            read_address <= a;
        end
    end
    ngage_bram_be #(
        .AW(6)
    ) scratch_ram (
        .clk  (clk),
        .raddr(scratch_index),
        .rdata(scratch_q),
        .waddr(scratch_index),
        .we   ((!reset && req && commit && we && scratch_hit) ? sel : 4'b0),
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
    wire [63:0] selected, missing;
    wire [31:0] data_tree[0:126];
    genvar slot;
    generate
        for (slot = 0; slot < 11; slot = slot + 1) begin : boot_latches
            assign selected[slot]     = a == boot_address(slot);
            assign missing[slot]      = selected[slot] && ((valid[slot] & sel) != sel);
            assign data_tree[63+slot] = selected[slot] ? values[slot] & mask : 32'b0;
            always @(posedge clk) begin
                if (reset) begin
                    values[slot] <= 0;
                    valid[slot]  <= slot == 6 ? 4'hf : 0;
                end else if (req && commit && we && selected[slot]) begin
                    values[slot] <= (values[slot] & ~mask) | (din & mask);
                    valid[slot]  <= valid[slot] | sel;
                end
            end
        end
        for (slot = 0; slot < 45; slot = slot + 1) begin : scratch_latches
            assign selected[11+slot]  = a == (32'h0c004748 + slot * 4);
            assign missing[11+slot]   = selected[11+slot] && ((scratch_valid[slot] & sel) != sel);
            assign data_tree[74+slot] = 0;
            always @(posedge clk) begin
                if (reset) begin
                    scratch_valid[slot] <= 0;
                end else if (req && commit && we && selected[11+slot]) begin
                    scratch_valid[slot] <= scratch_valid[slot] | sel;
                end
            end
        end
        for (slot = 56; slot < 64; slot = slot + 1) begin : unused_leaves
            assign selected[slot]     = 0;
            assign missing[slot]      = 0;
            assign data_tree[63+slot] = 0;
        end
        for (slot = 0; slot < 63; slot = slot + 1) begin : data_nodes
            assign data_tree[slot] = data_tree[2*slot+1] | data_tree[2*slot+2];
        end
    endgenerate
    always @* begin
        claim = req && (|selected);
        bad   = claim && !we && (|missing);
        // Unwritten bytes remain zero after warm reset even though the RAM
        // itself is not reset. Scratch reads expose all valid stored bytes.
        dout  = !req ? 32'b0 : scratch_hit ? (scratch_q & scratch_mask) : data_tree[0];
    end
endmodule
