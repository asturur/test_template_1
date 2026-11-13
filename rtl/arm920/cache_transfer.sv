// SPDX-License-Identifier: GPL-3.0-or-later
// Single-line replacement bus engine. Inputs are captured on start; successful
// completion is the only point at which the caller may discard a dirty victim.
// Each bus request remains stable until ack or err. A bus error aborts the
// operation; an interrupted write-back is safe to retry with the retained line.
module arm920_cache_transfer #(
    parameter LINE_REFILL = 0
) (

    output wire line_req,
    output wire [31:0] line_addr,
    input wire line_ready,
    input wire line_reject,
    input wire line_valid,
    input wire [63:0] line_data,
    input wire line_wide,
    input wire line_last,
    input wire line_error,

    input  logic         clk,
    input  logic         reset,
    input  logic         start,
    input  logic [ 31:0] victim_address,
    input  logic [  1:0] victim_dirty,
    input  logic [255:0] victim_line,
    input  logic [ 31:0] refill_address,
    output logic         busy,
    output logic         done,
    output logic         error,
    output logic [255:0] refill_line,
    output logic         bus_valid,
    output logic         bus_write,
    output logic [ 31:0] bus_address,
    output logic [ 31:0] bus_wdata,
    input  logic         bus_ack,
    input  logic         bus_error,
    input  logic [ 31:0] bus_rdata
);
  typedef enum logic [2:0] {
    IDLE,
    WRITEBACK,
    REFILL,
    LINE_REQUEST,
    LINE_WAIT
  } state_t;
  state_t state;
  logic [31:0] old_address, new_address;
  reg [3:0] half_index;
  integer lane;
  wire line_target = (new_address[31:24] == 8'h0a) ||
                       (new_address < 32'h007f0000) ||
                       (new_address >= 32'h02000000 && new_address < 32'h02400000) ||
                       (new_address >= 32'h04000000 && new_address < 32'h04800000);
  assign line_req  = LINE_REFILL && state == LINE_REQUEST;
  assign line_addr = new_address;


  logic [  1:0] dirty;
  logic [255:0] old_line;
  logic [  2:0] word_index;
  assign busy        = state != IDLE;
  assign bus_valid   = state == WRITEBACK || state == REFILL;
  assign bus_write   = state == WRITEBACK;
  assign bus_address = (bus_write ? old_address : new_address) + {27'b0, word_index, 2'b00};
  assign bus_wdata   = old_line[word_index*32+:32];
  // synthesis translate_off
  always @(posedge clk)
    if (!reset && state == LINE_WAIT && line_valid && !line_error) begin
      if (line_wide && half_index[1:0] != 0) $fatal(1, "unaligned wide line beat");
      if (line_last != (half_index + (line_wide ? 4 : 1) == 16)) $fatal(1, "bad line length");
    end
  // synthesis translate_on
  always_ff @(posedge clk) begin
    if (reset) begin
      state       <= IDLE;
      done        <= 0;
      error       <= 0;
      word_index  <= 0;
      half_index  <= 0;
      old_address <= 0;
      new_address <= 0;
      dirty       <= 0;
      old_line    <= 0;
      refill_line <= 0;
    end else begin
      done  <= 0;
      error <= 0;
      case (state)
        IDLE:
        if (start) begin
          old_address <= {victim_address[31:5], 5'b0};
          new_address <= {refill_address[31:5], 5'b0};
          old_line    <= victim_line;
          dirty       <= victim_dirty;
          refill_line <= 0;
          word_index  <= victim_dirty[0] ? 0 : victim_dirty[1] ? 4 : 0;
          if (|victim_dirty) state <= WRITEBACK;
          else state <= LINE_REFILL ? LINE_REQUEST : REFILL;
        end
        WRITEBACK:
        if (bus_error) begin
          state <= IDLE;
          done  <= 1;
          error <= 1;
        end else if (bus_ack) begin
          if (word_index == 3 && dirty[1]) word_index <= 4;
          else if (word_index == 3 || word_index == 7) begin
            word_index <= 0;
            state      <= LINE_REFILL ? LINE_REQUEST : REFILL;
          end else word_index <= word_index + 1'b1;
        end
        LINE_REQUEST: begin
          half_index <= 0;
          if (!line_target) state <= REFILL;
          else if (line_ready) state <= LINE_WAIT;
        end
        LINE_WAIT:
        if (line_reject) state <= REFILL;
        else if (line_valid) begin
          // Static 16-bit slices avoid a 256-bit variable write mux.
          for (lane = 0; lane < 16; lane = lane + 1)
          if (lane >= half_index && lane < half_index + (line_wide ? 4 : 1))
            refill_line[lane*16+:16] <= line_data[((lane-half_index)&3)*16+:16];
          half_index <= half_index + (line_wide ? 4 : 1);
          if (line_error || line_last) begin
            done  <= 1;
            error <= line_error;
            state <= IDLE;
          end
        end
        REFILL:
        if (bus_error) begin
          state <= IDLE;
          done  <= 1;
          error <= 1;
        end else if (bus_ack) begin
          refill_line[word_index*32+:32] <= bus_rdata;
          if (word_index == 7) begin
            state <= IDLE;
            done  <= 1;
          end else word_index <= word_index + 1'b1;
        end
        default: state <= IDLE;
      endcase
    end
  end
endmodule
