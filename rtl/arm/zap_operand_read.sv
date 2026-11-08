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
        output [31:0]               o_commit_c
);
reg head_valid, tail_valid;
reg [CONTROL_W-1:0] head_control, tail_control;
reg [23:0] head_index, tail_index;
reg [127:0] head_data, tail_data;
// Each slot base includes every commit except the immediately preceding edge.
// That last edge is represented by a shared data journal and per-owner one-hot
// selectors (C > B > A). Issue sees both pieces, plus current writes, in its one
// late-forwarding selection. No live write data feeds the queue's base registers.
reg [31:0] commit_a, commit_b, commit_c;
reg [11:0] head_pending, tail_pending;
wire [11:0] capture_match, head_match, tail_match;
wire capture_head = i_push && (!head_valid || i_pop);
wire promote_head = i_pop && tail_valid;
wire hold_head = !capture_head && !promote_head;

assign o_valid = head_valid;
assign o_full = tail_valid;
assign o_busy = head_valid;
assign o_control = head_control;
assign o_base_data = head_data;
assign o_pending = head_pending;
assign o_commit_a = commit_a;
assign o_commit_b = commit_b;
assign o_commit_c = commit_c;

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
                wire [2:0] hp = head_pending[3*port_no +: 3];
                wire [2:0] tp = tail_pending[3*port_no +: 3];
                // Resolve ownership and pending-write priority on narrow masks
                // before selecting words. Promotion must fold the TAIL journal.
                wire [2:0] fold_head = ({3{hold_head}} & hp) |
                                               ({3{promote_head}} & tp);
                wire [2:0] fold_tail = {3{!i_push}} & tp;
                assign capture_match[3*port_no +: 3] = commit_match(i_index[6*port_no +: 6]);
                assign head_match[3*port_no +: 3] = commit_match(head_index[6*port_no +: 6]);
                assign tail_match[3*port_no +: 3] = commit_match(tail_index[6*port_no +: 6]);
                always @(posedge i_clk)
                begin
                        head_data[32*port_no +: 32] <=
                                (i_data[32*port_no +: 32] & {32{capture_head}}) |
                                (head_data[32*port_no +: 32] & {32{hold_head && !(|hp)}}) |
                                (tail_data[32*port_no +: 32] & {32{promote_head && !(|tp)}}) |
                                (commit_a & {32{fold_head[0]}}) |
                                (commit_b & {32{fold_head[1]}}) |
                                (commit_c & {32{fold_head[2]}});
                        // Speculative capture into an INVALID reserve is safe:
                        // its validity still follows ordered queue ownership.
                        // A live reserve implies full, which forbids i_push.
                        // This removes pop/hazard from the reserve word enables.
                        tail_data[32*port_no +: 32] <=
                                (i_data[32*port_no +: 32] & {32{i_push}}) |
                                (tail_data[32*port_no +: 32] & {32{!i_push && !(|tp)}}) |
                                (commit_a & {32{fold_tail[0]}}) |
                                (commit_b & {32{fold_tail[1]}}) |
                                (commit_c & {32{fold_tail[2]}});
                end
        end
endgenerate

always @(posedge i_clk)
begin
        // Unconditional journal advance, including all data/shifter holds.
        // The narrow selector is zero when its corresponding port did not write.
        commit_a <= i_wr_data_a;
        commit_b <= i_wr_data_b;
        commit_c <= i_wr_data_c;
        head_pending <= capture_head ? capture_match :
                        promote_head ? tail_match : head_match;
        tail_pending <= i_push ? capture_match : tail_match;
        if (i_reset || i_clear)
        begin
                head_valid <= 1'b0;
                tail_valid <= 1'b0;
                head_pending <= 12'd0;
                tail_pending <= 12'd0;
        end
        else
        begin
                if (i_pop)
                begin
                        head_valid <= tail_valid;
                        tail_valid <= 1'b0;
                        if (tail_valid)
                        begin
                                head_control <= tail_control;
                                head_index <= tail_index;
                        end
                end
                if (i_push)
                begin
                        // No admission while full, even if popping this edge.
                        // Reserve contents may be speculative while invalid.
                        tail_control <= i_control;
                        tail_index <= i_index;
                        if (!head_valid || i_pop)
                        begin
                                head_valid <= 1'b1;
                                head_control <= i_control;
                                head_index <= i_index;
                        end
                        else
                                tail_valid <= 1'b1;
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
        end
end
`endif
endmodule
