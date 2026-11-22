`timescale 1ns / 1ps

module shift_pipeline_tb;
  reg clk = 0;
  always #5 clk = !clk;
  reg [31:0] operand;
  reg [1:0] kind;
  reg [7:0] count;
  reg capture = 0;
  reg is_register, carry_in;
  wire [4:0] amount = kind == 0 ? -count[4:0] : count[4:0];
  wire [34:0] combined, split;
  reg [34:0] expected;
  integer shift_type, shift_count, pattern, directed = 0;

  // Independent one-bit steps also cover counts above the word size.
  function [34:0] reference;
    input reg [31:0] value;
    input reg [1:0] shift_kind;
    input reg [7:0] shift_count;
    input reg register_shift, in_carry;
    reg [31:0] result;
    reg carry, preserve, rrx;
    integer steps, bit_index;
    begin
      result = value;
      carry = in_carry;
      preserve = 0;
      rrx = 0;
      steps = shift_count;
      if (steps == 0)
        if (register_shift || shift_kind == 0) preserve = 1;
        else if (shift_kind == 3) begin
          {carry, result} = {value[0], in_carry, value[31:1]};
          rrx = 1;
        end else steps = 32;
      for (bit_index = 0; bit_index < steps; bit_index = bit_index + 1)
      case (shift_kind)
        0: {carry, result} = {result, 1'b0};
        1: {carry, result} = {result[0], 1'b0, result[31:1]};
        2: {carry, result} = {result[0], result[31], result[31:1]};
        3: {carry, result} = {result[0], result[0], result[31:1]};
      endcase
      reference = {result, carry, preserve, rrx};
    end
  endfunction
  ngage2_arm9v2_rotate #(
      .PRE_ROT(1)
  ) same_cycle (
      .i_clk(1'b0),
      .i_capture(1'b0),
      .i_value(operand),
      .i_type(kind),
      .i_amount(count),
      .i_rot(amount),
      .i_register(is_register),
      .i_carry(carry_in),
      .o_value(combined[34:3]),
      .o_carry(combined[2]),
      .o_preserve(combined[1]),
      .o_rrx(combined[0])
  );
  ngage2_arm9v2_rotate #(
      .PRE_ROT(1),
      .REGISTER_STAGE(1)
  ) two_cycle (
      .i_clk(clk),
      .i_capture(capture),
      .i_value(operand),
      .i_type(kind),
      .i_amount(count),
      .i_rot(amount),
      .i_register(1'b1),
      .i_carry(carry_in),
      .o_value(split[34:3]),
      .o_carry(split[2]),
      .o_preserve(split[1]),
      .o_rrx(split[0])
  );

  initial begin
    for (shift_type = 0; shift_type < 4; shift_type = shift_type + 1) begin
      for (shift_count = 0; shift_count < 256; shift_count = shift_count + 1) begin
        for (pattern = 0; pattern < 16; pattern = pattern + 1) begin
          @(negedge clk);
          count = shift_count[7:0];
          kind = shift_type[1:0];
          operand = (32'h923f7ca1 * pattern) ^ (32'h81a16573 * shift_count);
          is_register = 1;
          carry_in = pattern[1];
          capture = 1;
          #1;
          expected = reference(operand, kind, count, is_register, carry_in);
          if (combined !== expected) $fatal(1, "Common register shift disagrees");
          @(negedge clk);
          capture = 0;
          if (split !== expected)
            $fatal(1, "Registered shift mismatch type=%0d count=%0d", shift_type, shift_count);
          is_register = 0;
          if (shift_count < 32) begin
            #1;
            if (combined !== reference(operand, kind, count, is_register, carry_in))
              $fatal(1, "Immediate shift or RRX disagrees");
          end
          count = ~count;
          kind = ~kind;
          operand = ~operand;
          carry_in = ~carry_in;
          @(negedge clk);
          if (split !== expected) $fatal(1, "Held result followed a later input");
          directed = directed + 1;
        end
      end
    end
    $display("PASS rotate: %0d staged register/hold cases and 2048 immediate cases", directed);
    $finish;
  end
endmodule
