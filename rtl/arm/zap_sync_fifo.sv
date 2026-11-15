//
//  (C)2016-2024 Revanth Kamaraj (krevanth) <revanth91kamaraj@gmail.com>
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 3
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
// 02110-1301, USA.
//
// This is a classic synchronous FIFO.
//

module zap_sync_fifo #(
    parameter logic [31:0] WIDTH = 32'd32,
    parameter logic [31:0] DEPTH = 32'd32
) (
    // Clock and reset
    input logic i_clk,
    input logic i_reset,

    // Flow control
    input logic i_ack,
    input logic i_wr_en,

    // Data busses
    input  logic [WIDTH-1:0] i_data,
    output logic [WIDTH-1:0] o_data,

    // Controls.
    input logic i_clear,

    // Flags
    output logic o_empty,
    output logic o_empty_n,
    output logic o_full,
    output logic o_full_n
);

  localparam [31:0] PTR_WDT = $clog2(DEPTH) + 32'd1;

  // Variables
  logic [PTR_WDT-1:0] rptr_ff, rptr_nxt;
  logic [PTR_WDT-1:0] wptr_ff, wptr_nxt;
  logic empty_ff, empty_nxt;
  logic full_ff, full_nxt;
  logic [WIDTH-1:0] mem      [DEPTH-1:0];
  logic             write_ok;
  logic             read_ok;
  logic [PTR_WDT-1:0] wptr_inc, rptr_inc;
  logic one_left, one_free;

  // Drive outputs.
  assign o_empty = empty_ff;
  assign o_empty_n = ~o_empty;
  assign o_full_n = ~o_full;
  assign o_full = full_ff;
  assign o_data = mem[rptr_ff[PTR_WDT-2:0]];

  // Compare registered pointers before the late transfer enables arrive.
  // A simultaneous accepted read/write preserves occupancy. At the empty/full
  // boundary the existing guards admit only the legal transfer, as before.
  assign wptr_inc = wptr_ff + 1'b1;
  assign rptr_inc = rptr_ff + 1'b1;
  assign one_left = wptr_ff == rptr_inc;
  assign one_free = wptr_inc == {~rptr_ff[PTR_WDT-1], rptr_ff[PTR_WDT-2:0]};
  always_comb begin
    empty_nxt = empty_ff;
    full_nxt = full_ff;
    case ({write_ok, read_ok})
      2'b10: begin
        empty_nxt = 1'b0;
        full_nxt = one_free;
      end
      2'b01: begin
        empty_nxt = one_left;
        full_nxt = 1'b0;
      end
      default: ;
    endcase
    if (i_clear) begin
      empty_nxt = 1'b1;
      full_nxt = 1'b0;
    end
  end

  always_ff @(posedge i_clk) begin
    if (i_reset) begin
      empty_ff <= 1'd1;
      full_ff  <= 1'd0;
    end else begin
      empty_ff <= empty_nxt;
      full_ff  <= full_nxt;
    end
  end

  // Guard conditions for IO operations.
  assign write_ok = i_wr_en & ~o_full;
  assign read_ok  = i_ack & ~o_empty;

  // FIFO write.
  always_ff @(posedge i_clk) begin
    if (write_ok) begin
      mem[wptr_ff[PTR_WDT-2:0]] <= i_data;
    end
  end

  // Pointer updates.
  assign wptr_nxt = i_clear ? 'd0 : (write_ok ? wptr_inc : wptr_ff);
  assign rptr_nxt = i_clear ? 'd0 : (read_ok ? rptr_inc : rptr_ff);

  always_ff @(posedge i_clk) begin
    if (i_reset) begin
      rptr_ff <= '0;
      wptr_ff <= '0;
    end else begin
      rptr_ff <= rptr_nxt;
      wptr_ff <= wptr_nxt;
    end
  end

endmodule : zap_sync_fifo

// ----------------------------------------------------------------------------
// END OF FILE
// ----------------------------------------------------------------------------
