// SPDX-License-Identifier: GPL-3.0-or-later
// Four address groups / sixteen words. Acceptance durably reserves capacity
// and hazards; a one-clock local commit makes the captured payload issuable.
// Reservations pipeline at one per clock, without an extra queue entry.
// Buffered writes cannot generate architectural external aborts. An unexpected
// bus error is latched and the current beat retained for an explicit retry.
module arm920_write_buffer (
    input logic clk,
    reset,
    input logic push_valid,
    output logic push_ready,
    input logic [31:0] push_address,
    input logic [2:0] push_words,
    input logic [127:0] push_data,
    input logic [15:0] push_byte_enable,
    output logic empty,
    full,
    output logic [2:0] entries,
    input logic [31:0] query_line_address,
    output logic query_line_pending,
    output logic bus_valid,
    output logic [31:0] bus_address,
    bus_data,
    output logic [3:0] bus_byte_enable,
    input logic bus_ack,
    bus_error,
    output logic error_latched,
    input logic clear_error
);
  logic [31:0] addresses[0:3];
  logic [2:0] lengths[0:3], committed_lengths[0:3];
  logic [26:0] last_line[0:3];
  logic [127:0] data[0:3];
  logic [15:0] enables[0:3];
  logic [1:0] head, tail, word_index;
  logic [2:0] count;
  // The summary is updated at reservation, including uncommitted words. Merge
  // no longer reads a tail-selected address/length array before bulk enables.
  logic [1:0] tail_slot;
  logic [2:0] tail_length;
  logic [31:0] tail_next_address;
  wire [31:0] push_last_address = push_address + {27'b0, (push_words - 3'd1), 2'b0};
  wire [31:0] push_next_address = push_address + {27'b0, push_words, 2'b0};
  wire beat_done = bus_valid && bus_ack && !bus_error;
  wire group_done = beat_done && ({1'b0, word_index} + 3'd1 == lengths[head]);
  wire merge_single=count!=0 && push_words==1 && tail_length<4 &&
                  push_address==tail_next_address &&
                  !(group_done && head==tail_slot);
  wire push = push_valid && push_ready;
  wire new_group = push && !merge_single;
  wire [1:0] reserve_slot = merge_single ? tail_slot : tail;
  wire [2:0] reserve_length = merge_single ? tail_length + 3'd1 : push_words;
  // Candidate data is sampled unconditionally: live ACK/allocation only drives
  // narrow reservation records, never the wide payload register enable.
  logic [127:0] pending_data;
  logic [15:0] pending_byte_enable, pending_word_enable;
  logic pending_valid, pending_merge;
  logic [1:0] pending_slot;
  logic [2:0] pending_length;
  always_ff @(posedge clk) begin
    pending_data <= push_data;
    pending_byte_enable <= push_byte_enable;
    pending_merge <= merge_single;
    pending_slot <= reserve_slot;
    pending_length <= reserve_length;
    if (reset) pending_valid <= 0;
    else pending_valid <= push;
  end
  // Reserved metadata is immediately visible to empty/capacity/alias queries.
  // Only committed words can be offered. A pending final word therefore cannot
  // retire or recycle its slot before the corresponding local commit edge.
  wire [3:0] pending_lines;
  genvar slot, word, byte_lane;
  generate
    for (slot = 0; slot < 4; slot = slot + 1) begin : slots
      wire [1:0] distance_from_head = slot - head;
      assign pending_lines[slot] = {1'b0,distance_from_head}<count &&
    (addresses[slot][31:5]==query_line_address[31:5] ||
     last_line[slot]==query_line_address[31:5]);
      always_ff @(posedge clk) begin
        if (reset) committed_lengths[slot] <= 0;
        else if (new_group && tail == slot) committed_lengths[slot] <= 0;
        else if (pending_valid && pending_slot == slot) committed_lengths[slot] <= pending_length;
        if (!reset) begin
          if (new_group && tail == slot) begin
            addresses[slot] <= push_address;
            lengths[slot]   <= push_words;
            last_line[slot] <= push_last_address[31:5];
          end else if (push && merge_single && tail_slot == slot) begin
            lengths[slot]   <= reserve_length;
            last_line[slot] <= push_address[31:5];
          end
        end
      end
      for (word = 0; word < 4; word = word + 1) begin : words
        always_ff @(posedge clk) begin
          if (reset) pending_word_enable[slot*4+word] <= 0;
          else
            pending_word_enable[slot*4+word]<=push && reserve_slot==slot &&
       (merge_single ? tail_length==word : word<push_words);
        end
        for (byte_lane = 0; byte_lane < 4; byte_lane = byte_lane + 1) begin : bytes
          always_ff @(posedge clk)
            if (!reset && pending_word_enable[slot*4+word]) begin
              data[slot][word*32+byte_lane*8+:8]<=pending_merge ?
       pending_data[byte_lane*8+:8] : pending_data[word*32+byte_lane*8+:8];
              enables[slot][word*4+byte_lane]<=pending_merge ?
       pending_byte_enable[byte_lane] : pending_byte_enable[word*4+byte_lane];
            end
        end
      end
    end
  endgenerate
  assign query_line_pending = |pending_lines;
  assign empty = count == 0;
  assign full = count == 4;
  assign entries = count;
  assign bus_valid = !empty && {1'b0, word_index} < committed_lengths[head] && !error_latched;
  assign bus_address = addresses[head] + {28'b0, word_index, 2'b0};
  assign bus_data = data[head][word_index*32+:32];
  assign bus_byte_enable = enables[head][word_index*4+:4];
  assign push_ready = !full || group_done || merge_single;
  always_ff @(posedge clk) begin
    if (reset) begin
      head <= 0;
      tail <= 0;
      count <= 0;
      word_index <= 0;
      error_latched <= 0;
      tail_slot <= 0;
      tail_length <= 0;
      tail_next_address <= 0;
    end else begin
      if (clear_error) error_latched <= 0;
      if (bus_valid && bus_error) error_latched <= 1;
      if (push) begin
        tail_slot <= reserve_slot;
        tail_length <= reserve_length;
        tail_next_address <= push_next_address;
      end
      if (new_group) tail <= tail + 1'b1;
      if (beat_done) begin
        if (group_done) begin
          head <= head + 1'b1;
          word_index <= 0;
        end else word_index <= word_index + 1'b1;
      end
      case ({
        new_group, group_done
      })
        2'b10:   count <= count + 1'b1;
        2'b01:   count <= count - 1'b1;
        default: ;
      endcase
    end
  end
  // synthesis translate_off
`ifndef SYNTHESIS
  // Generations are a simulation oracle, not another hardware decision cone.
  reg [3:0] generation;
  reg pending_generation;
  integer check_slot;
  always @(posedge clk) begin
    if (reset) begin
      generation <= 0;
      pending_generation <= 0;
    end else begin
      if (new_group) generation[tail] <= !generation[tail];
      if (push) pending_generation <= new_group ? !generation[tail] : generation[tail_slot];
      if(pending_valid && (pending_generation!=generation[pending_slot] ||
       (new_group && tail==pending_slot) || count==0))
        $fatal(1, "write-buffer pending commit lost its reserved generation");
      if (push && (push_words == 0 || push_words > 4))
        $fatal(1, "write buffer group must contain one to four words");
      if (count != 0 && (tail_slot != (tail - 2'd1) || tail_length != lengths[tail_slot]))
        $fatal(1, "write-buffer tail summary differs from reserved group");
      for (check_slot = 0; check_slot < 4; check_slot = check_slot + 1)
      if({1'b0,2'(check_slot-head)}<count && committed_lengths[check_slot]>lengths[check_slot])
        $fatal(1, "write-buffer committed length exceeds reservation");
    end
  end
`endif
  // synthesis translate_on
endmodule
