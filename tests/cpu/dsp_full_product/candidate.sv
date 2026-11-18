//
// (C)2016-2024 Revanth Kamaraj (krevanth) <revanth91kamaraj@gmail.com>
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
// This unit handles 32x32=32/64 multiplication using an FSM using
// a 17x17 signed array multiplier. Takes 5 cycles per 32x32+64 operation.
//

module dsp_full_product_candidate
#(
        parameter logic [31:0] PHY_REGS  = 32'd46,
        parameter logic [31:0] ALU_OPS   = 32'd32
)
(
        input logic                              i_clk,
        input logic                              i_reset,

        // Clear and stall signals.
        input logic                              i_clear_from_writeback,
        input logic                              i_data_stall,
        input logic                              i_clear_from_alu,

        // ALU operation to perform. Activate if this is multiplication.
        input logic   [$clog2(ALU_OPS)-1:0]      i_alu_operation_ff,

        // This is not used.
        input logic                              i_cc_satisfied,

        // rm.rs + {rh,rn}. For non accumulate versions, rn = 0x0 and rh = 0x0.
        input logic [31:0]                       i_rm,
        input logic [31:0]                       i_rn,
        input logic [31:0]                       i_rh,
        input logic [31:0]                       i_rs,

        //
        // Outputs.
        //

        output logic  [31:0]                      o_rd,    // Result.
        output logic                              o_sat,
        output logic                              o_busy,  // Unit busy.
        output logic                              o_nozero // Don't set zero flag.
);

`include "zap_defines.svh"
`include "zap_localparams.svh"

///////////////////////////////////////////////////////////////////////////////

// States

localparam [31:0] NUMBER_OF_STATES = 5;

typedef enum logic [NUMBER_OF_STATES-1:0] {
        IDLE          = 5'b00001,
        POST_IDLE     = 5'b00010,
        S1            = 5'b00100,
        S2            = 5'b01000,
        S3            = 5'b10000,
        `ZAP_DEFAULT_XX
} t_state;

///////////////////////////////////////////////////////////////////////////////

logic         old_nozero_nxt, old_nozero_ff;
logic         higher;
logic         unused;

assign unused = |{PHY_REGS};

// Set 1 to select the upper 32-bit result of an ARMv4 long multiply.
assign higher = i_alu_operation_ff[0];

// Full signed33-bit operands cover signed and unsigned ARM32 inputs exactly.
logic signed [32:0] factor_a, factor_b;
(* multstyle = "dsp" *) logic signed [65:0] full_product;
logic signed [63:0] x_ff, x_nxt;
t_state state_ff, state_nxt;
always_ff @(posedge i_clk) begin
    factor_a <= $signed({((i_alu_operation_ff == {1'd0,SMLALL} ||
                           i_alu_operation_ff == {1'd0,SMLALH}) && i_rm[31]),i_rm});
    factor_b <= $signed({((i_alu_operation_ff == {1'd0,SMLALL} ||
                           i_alu_operation_ff == {1'd0,SMLALH}) && i_rs[31]),i_rs});
    full_product <= factor_a * factor_b;
end

// STATE MACHINE ( Next State Logic )
always_comb
begin

        // --------------------------------------------------
        // Local Variable Section
        // --------------------------------------------------


        // --------------------------------------------------
        // Default Values Section
        // (Done to avoid combo loops/incomplete assignments
        // --------------------------------------------------

        old_nozero_nxt = old_nozero_ff;
        o_nozero       = 1'd0;
        o_busy         = 1'd1;
        o_rd           = 32'd0;
        state_nxt      = state_ff;
        x_nxt          = x_ff;
        o_sat          = 1'd0;

        // --------------------------------------------------
        // Main FSM code
        // --------------------------------------------------

        case ( state_ff )
                IDLE:
                begin
                        // If we have the go signal.
                        if ( i_cc_satisfied && (i_alu_operation_ff == {1'd0, UMLALL} ||
                                                i_alu_operation_ff == {1'd0, UMLALH} ||
                                                i_alu_operation_ff == {1'd0, SMLALL} ||
                                                i_alu_operation_ff == {1'd0, SMLALH} )
                        )
                        begin
                                state_nxt = POST_IDLE;
                        end
                        else
                        begin
                                o_busy = 1'd0;
                        end
                end

                POST_IDLE:
                begin
                        state_nxt = !higher ? S1 : S3;
                end

                S1:
                begin
                        // 3 input adder.
                        x_nxt     = full_product[63:0];
                        state_nxt = S2;
                end

                S2:
                begin
                        // 3 input adder.
                        x_nxt     = (x_ff[63:0]) + {i_rh, i_rn};

                        state_nxt = S3;
                end

                S3:
                begin
                        o_sat = 1'b0;

                        state_nxt  = IDLE;


                        // Is this the first or second portion of the long multiply.
                        o_rd  = higher ? x_nxt[63:32] : x_nxt[31:0];

                        // Record if older was not zero.
                        if ( !higher )
                        begin
                                old_nozero_nxt = |x_nxt[31:0]; // 0x1 - Older was not zero.
                                                               // 0x0 - Older was zero.
                        end

                        o_busy     = 1'd0;

                        //
                        // During higher operation, override setting of
                        // zero flag IF lower value was non-zero.
                        //
                        if ( higher && old_nozero_ff )
                        begin
                                o_nozero = 1'd1;
                        end
                end

                // ------------------------------------------
                // Default Section - Improves synth results.
                // ------------------------------------------

                default:
                begin
                        old_nozero_nxt = 'x;
                        o_nozero       = 'x;
                        o_busy         = 'x;
                        o_rd           = 'x;
                        state_nxt      = XX;
                        x_nxt          = 'x;
                        o_sat          = 'x;
                end
        endcase
end

///////////////////////////////////////////////////////////////////////////////

always_ff @ (posedge i_clk)
begin
        if ( i_reset )
        begin
                x_ff          <= 64'd0;
                state_ff      <= IDLE;
                old_nozero_ff <= 1'd0;
        end
        else if ( i_clear_from_writeback )
        begin
                state_ff      <= IDLE;
                old_nozero_ff <= 1'd0;
        end
        else if ( i_clear_from_alu && !i_data_stall )
        begin
                state_ff      <= IDLE;
                old_nozero_ff <= 1'd0;
        end
        else if ( !i_data_stall )
        begin
                x_ff          <= x_nxt;
                state_ff      <= state_nxt;
                old_nozero_ff <= old_nozero_nxt;
        end
end

///////////////////////////////////////////////////////////////////////////////

endmodule : dsp_full_product_candidate

// ----------------------------------------------------------------------------
// END OF FILE
// ----------------------------------------------------------------------------
