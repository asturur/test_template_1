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
        output [127:0]              o_data
);
reg head_valid, tail_valid;
reg [CONTROL_W-1:0] head_control, tail_control;
reg [23:0] head_index, tail_index;
reg [127:0] head_data, tail_data;
wire [127:0] capture_data, refreshed_head, refreshed_tail;

assign o_valid = head_valid;
assign o_full = tail_valid;
assign o_busy = head_valid;
assign o_control = head_control;
// Same-edge committed writes are visible to issue before the sampling edge.
assign o_data = refreshed_head;

function [31:0] committed_value;
        input [5:0] index;
        input [31:0] base;
        begin
                committed_value = base;
                if (i_wen && index == i_wr_addr_a)
                        committed_value = i_wr_data_a;
                if (i_wen && index == i_wr_addr_b)
                        committed_value = i_wr_data_b;
                if (index < 6'd40 && i_wr_addr_c[index])
                        committed_value = i_wr_data_c;
        end
endfunction

genvar port_no;
generate
        for (port_no = 0; port_no < 4; port_no = port_no + 1)
        begin : g_refresh
                assign capture_data[32*port_no +: 32] = committed_value(
                        i_index[6*port_no +: 6], i_data[32*port_no +: 32]);
                assign refreshed_head[32*port_no +: 32] = committed_value(
                        head_index[6*port_no +: 6], head_data[32*port_no +: 32]);
                assign refreshed_tail[32*port_no +: 32] = committed_value(
                        tail_index[6*port_no +: 6], tail_data[32*port_no +: 32]);
        end
endgenerate

always @(posedge i_clk)
begin
        // Refresh on every edge, including global data and multiply holds.
        head_data <= refreshed_head;
        tail_data <= refreshed_tail;
        if (i_reset || i_clear)
        begin
                head_valid <= 1'b0;
                tail_valid <= 1'b0;
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
                                head_data <= refreshed_tail;
                        end
                end
                if (i_push)
                begin
                        // No admission while full, even if popping this edge.
                        if (!head_valid || i_pop)
                        begin
                                head_valid <= 1'b1;
                                head_control <= i_control;
                                head_index <= i_index;
                                head_data <= capture_data;
                        end
                        else
                        begin
                                tail_valid <= 1'b1;
                                tail_control <= i_control;
                                tail_index <= i_index;
                                tail_data <= capture_data;
                        end
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
