// SPDX-License-Identifier: GPL-3.0-or-later
// Owned register-acquisition packets. Read addresses are supplied by decode;
// only registered packets feed issue. Full is occupancy-only, never pop-ready.
module zap_operand_read #(
        parameter CONTROL_W = 1
)(
        input                       i_clk,
        input                       i_reset,
        input                       i_clear,
        input                       i_push,
        input                       i_pop,
        input [CONTROL_W-1:0]       i_control,
        input [23:0]                i_index,
        input [127:0]               i_data,
        input                       i_wen,
        input [5:0]                 i_wr_addr_a,
        input [5:0]                 i_wr_addr_b,
        input [39:0]                i_wr_addr_c,
        input [31:0]                i_wr_data_a,
        input [31:0]                i_wr_data_b,
        input [31:0]                i_wr_data_c,
        output                      o_valid,
        output                      o_full,
        output                      o_busy,
        output [CONTROL_W-1:0]      o_control,
        output [127:0]              o_base_data,
        output [11:0]               o_pending,
        output [31:0]               o_commit_a,
        output [31:0]               o_commit_b,
        output [31:0]               o_commit_c,
        // Unselected owners feed parallel narrow forwarding decisions in I.
        output                      o_read_slot,
        output [CONTROL_W-1:0]      o_slot0_control,
        output [CONTROL_W-1:0]      o_slot1_control,
        output [23:0]               o_slot0_index,
        output [23:0]               o_slot1_index,
        output [11:0]               o_slot0_pending,
        output [11:0]               o_slot1_pending
);
// Logical occupancy is independent of physical slot selection. Payload never
// promotes: pop changes only the read pointer and occupancy; push writes the
// next free physical slot, without consulting pop/hazard in its data enable.
reg head_valid, tail_valid;
reg read_slot, write_slot;
reg [CONTROL_W-1:0] slot0_control, slot1_control;
reg [23:0] slot0_index, slot1_index;
reg [127:0] slot0_data, slot1_data;
reg [11:0] slot0_pending, slot1_pending;
reg [31:0] commit_a, commit_b, commit_c;
wire [11:0] capture_match, slot0_match, slot1_match;
wire capture0 = i_push && !write_slot;
wire capture1 = i_push && write_slot;

assign o_valid = head_valid;
assign o_full = tail_valid;
assign o_busy = head_valid;
assign o_control = read_slot ? slot1_control : slot0_control;
assign o_base_data = read_slot ? slot1_data : slot0_data;
assign o_pending = read_slot ? slot1_pending : slot0_pending;
assign o_commit_a = commit_a;
assign o_commit_b = commit_b;
assign o_commit_c = commit_c;
assign o_read_slot = read_slot;
assign o_slot0_control = slot0_control;
assign o_slot1_control = slot1_control;
assign o_slot0_index = slot0_index;
assign o_slot1_index = slot1_index;
assign o_slot0_pending = slot0_pending;
assign o_slot1_pending = slot1_pending;

function [2:0] commit_match;
        input [5:0] index;
        reg a, b, c;
        begin
                a = i_wen && index == i_wr_addr_a;
                b = i_wen && index == i_wr_addr_b;
                c = index < 6'd40 && i_wr_addr_c[index];
                commit_match = {c, b && !c, a && !b && !c};
        end
endfunction

genvar port_no;
generate
        for (port_no = 0; port_no < 4; port_no = port_no + 1)
        begin : g_refresh
                wire [2:0] p0 = slot0_pending[3*port_no +: 3];
                wire [2:0] p1 = slot1_pending[3*port_no +: 3];
                wire [2:0] fold0 = {3{!capture0}} & p0;
                wire [2:0] fold1 = {3{!capture1}} & p1;
                assign capture_match[3*port_no +: 3] = commit_match(i_index[6*port_no +: 6]);
                assign slot0_match[3*port_no +: 3] = commit_match(slot0_index[6*port_no +: 6]);
                assign slot1_match[3*port_no +: 3] = commit_match(slot1_index[6*port_no +: 6]);
                always @(posedge i_clk)
                begin
                        // Each physical owner folds its own previous journal,
                        // even across holds, pop or empty intervals. Capture
                        // replaces both base and selector with the new owner.
                        slot0_data[32*port_no +: 32] <=
                                (i_data[32*port_no +: 32] & {32{capture0}}) |
                                (slot0_data[32*port_no +: 32] & {32{!capture0 && !(|p0)}}) |
                                (commit_a & {32{fold0[0]}}) |
                                (commit_b & {32{fold0[1]}}) |
                                (commit_c & {32{fold0[2]}});
                        slot1_data[32*port_no +: 32] <=
                                (i_data[32*port_no +: 32] & {32{capture1}}) |
                                (slot1_data[32*port_no +: 32] & {32{!capture1 && !(|p1)}}) |
                                (commit_a & {32{fold1[0]}}) |
                                (commit_b & {32{fold1[1]}}) |
                                (commit_c & {32{fold1[2]}});
                end
        end
endgenerate

always @(posedge i_clk)
begin
        commit_a <= i_wr_data_a;
        commit_b <= i_wr_data_b;
        commit_c <= i_wr_data_c;
        slot0_pending <= capture0 ? capture_match : slot0_match;
        slot1_pending <= capture1 ? capture_match : slot1_match;
        if (i_reset || i_clear)
        begin
                head_valid <= 1'b0;
                tail_valid <= 1'b0;
                // Preserve the last exposed packet across clear/empty. The BTB
                // still observes bubble PCs when invalidating feedback entries.
                // Reset alone establishes a deterministic initial selector.
                if (i_reset)
                        read_slot <= 1'b0;
                write_slot <= i_reset ? 1'b0 : read_slot;
                slot0_pending <= 12'd0;
                slot1_pending <= 12'd0;
        end
        else
        begin
                if (i_pop && tail_valid)
                        read_slot <= !read_slot;
                else if (i_push && (!head_valid || i_pop))
                        read_slot <= write_slot;
                if (i_push)
                        write_slot <= !write_slot;
                case ({i_push, i_pop})
                2'b10: begin
                        head_valid <= 1'b1;
                        tail_valid <= head_valid;
                end
                2'b01: begin
                        head_valid <= tail_valid;
                        tail_valid <= 1'b0;
                end
                default: begin end // Hold, or one-entry pop+push: same count.
                endcase
                if (capture0)
                begin
                        slot0_control <= i_control;
                        slot0_index <= i_index;
                end
                if (capture1)
                begin
                        slot1_control <= i_control;
                        slot1_index <= i_index;
                end
        end
end
`ifndef SYNTHESIS
always @(posedge i_clk)
begin
        if (!i_reset && !i_clear)
        begin
                if (i_push && o_full)
                        $fatal(1, "operand queue accepted while full");
                if (i_pop && !o_valid)
                        $fatal(1, "operand queue popped while empty");
                if (tail_valid && !head_valid)
                        $fatal(1, "operand queue tail without head");
                if (head_valid && ((read_slot == write_slot) != tail_valid))
                        $fatal(1, "operand queue pointer/occupancy mismatch");
        end
end
`endif
endmodule
