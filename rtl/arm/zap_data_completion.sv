// SPDX-License-Identifier: GPL-3.0-or-later
// One blocking P2 demand owns its completion until the next CPU advance edge.
// Payload, abort/retry and fault context cross the boundary together. The offer
// is suppressed once captured, so a held P2 cannot replay an acknowledged store.
module zap_data_completion (
    input i_clk,
    i_reset,
    i_kill,
    input i_request,
    i_ack,
    input [31:0] i_data,
    i_fsr,
    i_far,
    input [1:0] i_fault,
    output o_offer,
    output reg o_valid,
    output reg [31:0] o_data,
    o_fsr,
    o_far,
    output reg [1:0] o_fault
);
  assign o_offer = i_request && !o_valid && !i_kill && !i_reset;
  always @(posedge i_clk) begin
    if (i_reset || i_kill) o_valid <= 1'b0;
    else begin
      // Consume exactly once. P2 and every dependent stage advance
      // together while valid; otherwise an active request must hold.
      o_valid <= o_offer && i_ack;
      if (o_offer && i_ack) begin
        o_data  <= i_data;
        o_fault <= i_fault;
        o_fsr   <= i_fsr;
        o_far   <= i_far;
      end
    end
  end
`ifndef SYNTHESIS
  always @(posedge i_clk)
    if (!i_reset && !i_kill && o_valid && !i_request)
      $fatal(1, "completion lost its held P2 owner");
`endif
endmodule
