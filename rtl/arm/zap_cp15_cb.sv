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
// This RTL describes the CP15 register block. The ports go to the MMU and
// cache unit. This block connects to the CPU core. Coprocessor operations
// supported are read from coprocessor and write to CPU registers or vice
// versa. This is integrated within the processor. The MMU unit can easily
// interface with this block.
//

// Quartus 17 compat: moved struct typedef out of parameter list
typedef struct packed {
        logic [11:0]  cp_rsvd_fld_1;          // 31:20 - 12 (32)
        logic [3:0]  ZAP_CRN;                 // 19:16 - 4 (20)
        logic [3:0]  cp_srvd_fld_0;           // 15:12 - 4 (16)
        logic [3:0]  ZAP_CP_ID;               // 11:8 - 4 (12)
        logic [2:0]  ZAP_OPCODE_2;            // 7:5 - 3 (8)
        logic [0:0]  cp_rsvd_fld;             // 4   - 1 (5)
        logic [3:0]  ZAP_CRM;                 // 3:0 - 4 (4)
} t_cp_instruction;

module zap_cp15_cb

#(
        parameter logic CP15_L4_DEFAULT          = 1'd0,
        parameter logic BE_32_ENABLE             = 1'd0,
        parameter logic ONLY_CORE                = 1'd0,

        parameter logic [31:0] PHY_REGS          = 32'd64,
        parameter logic [31:0] CODE_CACHE_LINE   = 32'd64,
        parameter logic [31:0] DATA_CACHE_LINE   = 32'd64,
        parameter logic [31:0] CODE_CACHE_SIZE   = 32'd1024,
        parameter logic [31:0] DATA_CACHE_SIZE   = 32'd1024
)
(
        // ----------------------------------------------------------------
        // Clock and reset.
        // ----------------------------------------------------------------

        input logic                              i_clk,
        input logic                              i_reset,

        // ----------------------------------------------------------------
        // Coprocessor instruction and done signal.
        // ----------------------------------------------------------------

        input t_cp_instruction                   i_cp_word,
        input logic                              i_cp_dav,
        output logic                             o_cp_done,

        // ----------------------------------------------------------------
        // CPSR from processor.
        // ----------------------------------------------------------------

        input  logic     [31:0]                  i_cpsr,

        // ----------------------------------------------------------------
        // Register file RW interface
        // ----------------------------------------------------------------

        // Asserted if we want to control of the register file.
        // Controls a MUX that selects signals.
        output logic                              o_reg_en,

        // Data to write to the register file.
        output logic [31:0]                       o_reg_wr_data,

        // Data read from the register file.
        input logic [31:0]                        i_reg_rd_data,

        // Write and read index for the register file.
        output logic [$clog2(PHY_REGS)-1:0]       o_reg_wr_index,
                                                  o_reg_rd_index,

        // ----------------------------------------------------------------
        // From MMU.
        // ----------------------------------------------------------------

        input logic      [31:0]                  i_fsr,
        input logic      [31:0]                  i_far,

        // -----------------------------------------------------------------
        // MMU configuration signals.
        // -----------------------------------------------------------------

        // Domain Access Control Register.
        output logic      [31:0]                  o_dac,

        // Base address of page table.
        output logic      [31:0]                  o_baddr,

        // MMU enable and ARM920T data-alignment checking.
        output logic                              o_mmu_en,
        output logic                              o_alignment_en,

        // SR register.
        output logic      [1:0]                   o_sr,

        // FCSE register.
        output logic      [7:0]                   o_pid,

        // L4 Enable
        output logic                              o_l4_enable,

        // -----------------------------------------------------------------
        // Invalidate and clean controls.
        // -----------------------------------------------------------------

        // Cache invalidate signal.
        output logic                              o_dcache_inv,
        output logic                              o_icache_inv,

        // Cache clean signal.
        output logic                              o_dcache_clean,
        output logic                              o_icache_clean,

        // TLB invalidate signal - single cycle.
        output logic                              o_dtlb_inv,
        output logic                              o_itlb_inv,
output logic o_tlb_inv_mva,
output logic [31:0] o_tlb_inv_address,
output logic o_dtlb_lock_write,
output logic o_itlb_lock_write,
output logic [31:0] o_tlb_lock_data,
input wire [31:0] i_dtlb_lock_read,
input wire [31:0] i_itlb_lock_read,


        // Cache enable.
        output logic                              o_dcache_en,
        output logic                              o_icache_en,
        output logic                              o_cache_rr,
        output logic                              o_dcache_lock_write,
        output logic [5:0]                        o_dcache_lock_base,
        output logic                              o_icache_lock_write,
        output logic [5:0]                        o_icache_lock_base,
        output logic                              o_icache_prefetch,
        input logic                               i_icache_prefetch_done,
        output logic                              o_drain_write_buffer,
        input logic                               i_write_buffer_empty,
        input logic                               i_irq,
        input logic                               i_fiq,
        output logic                              o_wfi_irq,
        output logic                              o_wfi_fiq,
        output logic                              o_cache_op_single,
        output logic                              o_cache_op_by_mva,
        output logic [31:0]                       o_cache_op_address,

        // From MMU. Specify that cache invalidation is done.
        input   logic                            i_dcache_lock_done,
        input   logic                            i_icache_lock_done,
        input   logic                            i_dcache_inv_done,
        input   logic                            i_icache_inv_done,

        // From MMU. Specify that cache clean is done.
        input   logic                            i_dcache_clean_done,
        input   logic                            i_icache_clean_done
);

`include "zap_localparams.svh"
`include "zap_defines.svh"
`include "zap_functions.svh"

// ---------------------------------------------
// Variables
// ---------------------------------------------

logic [31:0] r [13:0];// Coprocessor registers. R7, R8 is write-only.
logic [4:0]    state; // State variable.
logic          wait_for_interrupt;

// ---------------------------------------------
// Localparams
// ---------------------------------------------

// States.
localparam [3:0] IDLE                 = 0;
localparam [3:0] ACTIVE               = 1;
localparam [3:0] DONE                 = 2;
localparam [3:0] READ                 = 3;
localparam [3:0] READ_DLY             = 4;
localparam [3:0] TERM                 = 5;
localparam [3:0] CLR_D_CACHE_AND      = 6;
localparam [3:0] CLR_D_CACHE          = 7;
localparam [3:0] CLR_I_CACHE          = 8;
localparam [3:0] CLEAN_D_CACHE        = 9;
localparam [3:0] CLFLUSH_ID_CACHE     = 10;
localparam [3:0] CLFLUSH_D_CACHE      = 11;
localparam [3:0] LOCK_D_CACHE         = 12;
localparam [3:0] LOCK_I_CACHE         = 13;
localparam [3:0] DRAIN_WRITE_BUFFER    = 14;
localparam [3:0] WAIT_FOR_INTERRUPT    = 15;
localparam [4:0] ICACHE_PREFETCH       = 16;

// Register numbers.
localparam [3:0] FSR_REG              = 5;
localparam [3:0] FAR_REG              = 6;
localparam [3:0] CACHE_REG            = 7;
localparam [3:0] TLB_REG              = 8;

//{OPCODE_2, CRM} values that are valid for this implementation.
localparam [6:0] CASE_FLUSH_ID_CACHE       = 7'b000_0111;
localparam [6:0] CASE_FLUSH_I_CACHE        = 7'b000_0101;
localparam [6:0] CASE_FLUSH_D_CACHE        = 7'b000_0110;
localparam [6:0] CASE_CLEAN_ID_CACHE       = 7'b000_1011;
localparam [6:0] CASE_CLEAN_D_CACHE        = 7'b000_1010;
localparam [6:0] CASE_CLFLUSH_ID_CACHE     = 7'b000_1111;
localparam [6:0] CASE_CLFLUSH_D_CACHE      = 7'b000_1110;
localparam [6:0] CASE_DRAIN_WRITE_BUFFER     = 7'b100_1010;
localparam [6:0] CASE_WAIT_FOR_INTERRUPT     = 7'b100_0000;
localparam [6:0] CASE_FLUSH_ID_TLB         = 7'b00?_0111;
localparam [6:0] CASE_FLUSH_I_TLB          = 7'b00?_0101;
localparam [6:0] CASE_FLUSH_D_TLB          = 7'b00?_0110;

logic [1:0][11:0] xCACHE_TYPE_WORD;
logic [31:0]      CACHE_TYPE_WORD ; // Provides cache info.

assign xCACHE_TYPE_WORD[0][1:0]  = CODE_CACHE_LINE == 16 ? 2'd1 :
                                   CODE_CACHE_LINE == 32 ? 2'd2 : 2'd3;

assign xCACHE_TYPE_WORD[0][2]    = ONLY_CORE ? 1'd1 : 1'd0;

// Report the production ARM920T 64-way associative cache.
// EKA1 also uses this field to derive the increment in its maintenance loop.
assign xCACHE_TYPE_WORD[0][5:3]  = 3'd6;

always_comb
begin
        case(CODE_CACHE_SIZE)
        512  : xCACHE_TYPE_WORD[0][8:6] = 3'd0;
        1024 : xCACHE_TYPE_WORD[0][8:6] = 3'd1;
        2048 : xCACHE_TYPE_WORD[0][8:6] = 3'd2;
        4096 : xCACHE_TYPE_WORD[0][8:6] = 3'd3;
        8192 : xCACHE_TYPE_WORD[0][8:6] = 3'd4;
        16384: xCACHE_TYPE_WORD[0][8:6] = 3'd5;
        32768: xCACHE_TYPE_WORD[0][8:6] = 3'd6;
        65536: xCACHE_TYPE_WORD[0][8:6] = 3'd7;
        default:
        begin
                // Cannot happen - assign X to OPTIMIZE. OK to do for FPGA synth.
                xCACHE_TYPE_WORD[0][8:6] = {3{1'dx}};
                assert(ONLY_CORE) else $fatal(2, "Code cache size not in range.");
        end
        endcase
end

assign xCACHE_TYPE_WORD[0][11:9] = '0;

assign xCACHE_TYPE_WORD[1][1:0]  = DATA_CACHE_LINE == 16 ? 2'd1 :
                                   DATA_CACHE_LINE == 32 ? 2'd2 : 2'd3;

assign xCACHE_TYPE_WORD[1][2]    = ONLY_CORE ? 1'd1 : 1'd0;

assign xCACHE_TYPE_WORD[1][5:3]  = 3'd6; // See the icache note: ARM920T 64-way report.

always_comb
begin
        case(DATA_CACHE_SIZE)
        512  : xCACHE_TYPE_WORD[1][8:6] = 3'd0;
        1024 : xCACHE_TYPE_WORD[1][8:6] = 3'd1;
        2048 : xCACHE_TYPE_WORD[1][8:6] = 3'd2;
        4096 : xCACHE_TYPE_WORD[1][8:6] = 3'd3;
        8192 : xCACHE_TYPE_WORD[1][8:6] = 3'd4;
        16384: xCACHE_TYPE_WORD[1][8:6] = 3'd5;
        32768: xCACHE_TYPE_WORD[1][8:6] = 3'd6;
        65536: xCACHE_TYPE_WORD[1][8:6] = 3'd7;
        default:
        begin
                // Cannot happen - assign X to OPTIMIZE. OK to do for FPGA synth.
                xCACHE_TYPE_WORD[1][8:6] = {3{1'dx}};
                assert(ONLY_CORE) else $fatal(2, "Data cache size not in range.");
        end
        endcase
end

assign xCACHE_TYPE_WORD[1][11:9] = '0;

////////////////////////////////////////////////////////////////////////////

// Build the CACHE_TYPE word.
assign CACHE_TYPE_WORD[23:0]     = xCACHE_TYPE_WORD;
assign CACHE_TYPE_WORD[24]       = 1'd1;     // S = 1, split cache.
assign CACHE_TYPE_WORD[31:25]    = 7'b0000110; // ctype 6: write-back, c7 clean ops (ARM920T).

// ---------------------------------------------
// Sequential Logic
// ---------------------------------------------

// Ties registers to output ports via a register.
always_ff @ ( posedge i_clk )
begin
        if ( i_reset )
        begin
                o_dcache_en <= 1'd0;
                o_icache_en <= 1'd0;
                o_cache_rr <= 1'b0;
                o_mmu_en    <= 1'd0;
                o_alignment_en <= 1'd0;
                o_pid       <= 8'd0;
                o_l4_enable <= CP15_L4_DEFAULT;
        end
        else
        begin
                o_dcache_en <= r[1][2];              // Data cache enable.
                o_cache_rr <= r[1][14];
                o_icache_en <= r[1][12];             // Instruction cache enable.
                o_mmu_en    <= r[1][0];              // MMU enable.
                o_alignment_en <= r[1][1];          // Alignment fault enable.
                o_pid       <= {1'd0, r[13][31:25]}; // PID register.
                // ARM920 bit 14 controls cache replacement, not ISA version.
                // The N-Gage config fixes ARMv4T behavior; retain the legacy
                // selectable mode only for non-ARM920 configurations.
                o_l4_enable <= CP15_L4_DEFAULT ? 1'b1 : r[1][14];
        end
end

// Ties register ports via register.
always_ff @ ( posedge i_clk )
begin
        o_dac       <= r[3];                     // DAC register.
        o_baddr     <= r[2];                     // Base address.
        o_sr        <= {r[1][8],r[1][9]};        // SR register.
end



// Core logic.
always_ff @ ( posedge i_clk )
begin
        if ( i_reset )
        begin
                state          <= IDLE;
                o_drain_write_buffer <= 1'b0;
                o_icache_prefetch <= 1'b0;
                wait_for_interrupt <= 1'b0;
                o_wfi_irq <= 1'b0;
                o_wfi_fiq <= 1'b0;
                o_dcache_inv   <= 1'd0;
                o_dcache_lock_write <= 1'b0;
                o_dcache_lock_base <= 6'b0;
                o_icache_lock_write <= 1'b0;
                o_icache_lock_base <= 6'b0;
                o_cache_op_single <= 1'b0;
                o_cache_op_by_mva <= 1'b0;
                o_cache_op_address <= 32'b0;
                o_tlb_inv_mva <= 0; o_tlb_inv_address <= 0;
                o_dtlb_lock_write <= 0; o_itlb_lock_write <= 0; o_tlb_lock_data <= 0;
                o_icache_inv   <= 1'd0;
                o_dcache_clean <= 1'd0;
                o_icache_clean <= 1'd0;
                o_dtlb_inv     <= 1'd0;
                o_itlb_inv     <= 1'd0;
                o_reg_en       <= 1'd0;
                o_cp_done      <= 1'd0;
                o_reg_wr_data  <= 0;
                o_reg_wr_index <= 0;
                o_reg_rd_index <= 0;
                r[0]           <= 0;
                r[1]           <= 0;
                r[1][14]       <= 1'b0; // ARM920 RR: random replacement at reset
                r[2]           <= 32'd0;
                r[3]           <= 32'd0;
                r[4]           <= 32'd0;
                r[5]           <= 32'd0;
                r[6]           <= 32'd0;
                r[13]          <= 32'd0;
                r[0][15:4]     <= CP15_L4_DEFAULT ? 12'h920 : 12'hAAA;
                r[0][19:16]    <= CP15_L4_DEFAULT ? 4'h2 : 4'h5;
                r[0][23:20]    <= CP15_L4_DEFAULT ? 4'h1 : 4'h0;
                r[0][31:24]    <= CP15_L4_DEFAULT ? 8'h41 : 8'h00;
                r[1][7]        <= BE_32_ENABLE;
                r[1][6:3]      <= 4'b1111;
                r[1][11:10]    <= 2'b00; // ARM920 reserved: reads zero
        end
        else
        begin
                // ====================================
                // Default values section.
                // ====================================

                o_dcache_lock_write <= 1'b0;
                o_icache_lock_write <= 1'b0;
                o_dtlb_lock_write <= 0; o_itlb_lock_write <= 0;
                o_itlb_inv      <= 1'd0;
                o_dtlb_inv      <= 1'd0;
                o_dcache_inv    <= 1'd0;
                o_icache_inv    <= 1'd0;
                o_icache_clean  <= 1'd0;
                o_dcache_clean  <= 1'd0;
                o_reg_en        <= 1'd0;
                o_cp_done       <= 1'd0;

                // ===================================
                // FSM Code
                // ===================================

                case ( state )
                IDLE: // Idle state.
                begin
                        o_cp_done <= 1'd0;

                        // Keep monitoring FSR and FAR from MMU unit. If
                        // produced, clock them in.
                        if ( i_fsr[3:0] != 4'd0 )
                        begin
                                r[FSR_REG] <= i_fsr;
                                r[FAR_REG] <= i_far;
                        end

                        // Coprocessor instruction.
                        if ( i_cp_dav && i_cp_word.ZAP_CP_ID == 15 )
                        begin
                                if ( i_cpsr[ZAP_CPSR_MODE:0] != USR )
                                begin
                                        // ACTIVATE this block.
                                        state     <= ACTIVE;
                                        o_cp_done <= 1'd0;
                                end
                                else
                                begin
                                        // No permissions in USR land.
                                        // Pretend to be done and go ahead.
                                        o_cp_done <= 1'd1;
                                end
                        end
                end

                DONE: // Complete transaction.
                begin
                        // Tell that we are done.
                        o_cp_done    <= 1'd1;
                        state        <= TERM;
                end

                TERM: // Wait state before going to IDLE.
                begin
                        o_wfi_irq <= 1'b0;
                        o_wfi_fiq <= 1'b0;
                        state <= IDLE;
                end

                READ_DLY: // Register data is clocked out in this stage.
                begin
                        state <= READ;
                end

                READ: // Write value read from CPU register to coprocessor.
                begin
                        state <= DONE;

                        r [ i_cp_word.ZAP_CRN ] <= i_reg_rd_data;
                        if (CP15_L4_DEFAULT && i_cp_word.ZAP_CRN == 9 && i_cp_word.ZAP_CRM == 0) begin
                                if (i_cp_word.ZAP_OPCODE_2 == 0) begin
                                        o_dcache_lock_base <= i_reg_rd_data[31:26];
                                        o_dcache_lock_write <= 1'b1;
                                        state <= LOCK_D_CACHE;
                                end else if (i_cp_word.ZAP_OPCODE_2 == 1) begin
                                        o_icache_lock_base <= i_reg_rd_data[31:26];
                                        o_icache_lock_write <= 1'b1;
                                        state <= LOCK_I_CACHE;
                                end
                        end

                        if (i_cp_word.ZAP_CRN == 10 && i_cp_word.ZAP_CRM == 0) begin
                                o_tlb_lock_data <= i_reg_rd_data;
                                o_dtlb_lock_write <= i_cp_word.ZAP_OPCODE_2 == 0;
                                o_itlb_lock_write <= i_cp_word.ZAP_OPCODE_2 == 1;
                        end
                        if
                        (
                                i_cp_word.ZAP_CRN == TLB_REG  // TLB control.
                        )
                        begin
                                o_tlb_inv_mva <= i_cp_word.ZAP_OPCODE_2[0];
                                o_tlb_inv_address <= i_reg_rd_data;
                                casez({i_cp_word.ZAP_OPCODE_2,
                                       i_cp_word.ZAP_CRM})

                                CASE_FLUSH_ID_TLB:
                                begin
                                        o_itlb_inv  <= 1'd1;
                                        o_dtlb_inv  <= 1'd1;
                                end

                                CASE_FLUSH_I_TLB:
                                begin
                                        o_itlb_inv <= 1'd1;
                                end

                                CASE_FLUSH_D_TLB:
                                begin
                                        o_dtlb_inv <= 1'd1;
                                end

                                default:
                                begin
                                        o_itlb_inv <= 1'd1;
                                        o_dtlb_inv <= 1'd1;
                                end

                                endcase
                        end
                        else if ( i_cp_word.ZAP_CRN == CACHE_REG )
                        // Cache control selected. Operation details stay
                        // stable until the selected cache acknowledges.
                        begin
                                o_cache_op_single <= 1'b0;
                                o_cache_op_by_mva <= 1'b0;
                                o_cache_op_address <= i_reg_rd_data;
                                casez({i_cp_word.ZAP_OPCODE_2,
                                       i_cp_word.ZAP_CRM})

                                7'b001_0101: begin // Invalidate I line by MVA
                                        o_cache_op_single <= 1'b1;o_cache_op_by_mva <= 1'b1;
                                        o_icache_inv <= 1'b1;state <= CLR_I_CACHE;
                                end
                                7'b001_0110: begin // Invalidate D line by MVA
                                        o_cache_op_single <= 1'b1;o_cache_op_by_mva <= 1'b1;
                                        o_dcache_inv <= 1'b1;state <= CLR_D_CACHE;
                                end
                                7'b001_1010, 7'b010_1010: begin // Clean D by MVA/index
                                        o_cache_op_single <= 1'b1;o_cache_op_by_mva <= i_cp_word.ZAP_OPCODE_2 == 1;
                                        o_dcache_clean <= 1'b1;state <= CLEAN_D_CACHE;
                                end
                                7'b001_1110, 7'b010_1110: begin // Clean+invalidate D by MVA/index
                                        o_cache_op_single <= 1'b1;o_cache_op_by_mva <= i_cp_word.ZAP_OPCODE_2 == 1;
                                        o_dcache_clean <= 1'b1;state <= CLFLUSH_D_CACHE;
                                end
                                7'b001_1101: begin // Prefetch I-cache line by MVA
                                        o_icache_prefetch <= 1'b1;
                                        state <= ICACHE_PREFETCH;
                                end
                                CASE_WAIT_FOR_INTERRUPT:
                                begin
                                        wait_for_interrupt <= 1'b1;
                                        o_drain_write_buffer <= 1'b1;
                                        state <= DRAIN_WRITE_BUFFER;
                                end
                                CASE_DRAIN_WRITE_BUFFER:
                                begin
                                        wait_for_interrupt <= 1'b0;
                                        // Draining waits for all buffered writes, and does
                                        // not clean or invalidate the data cache.
                                        o_drain_write_buffer <= 1'b1;
                                        state <= DRAIN_WRITE_BUFFER;
                                end

                                CASE_FLUSH_ID_CACHE:
                                begin
                                        // Invalidate ALL caches.
                                        o_dcache_inv    <= 1'd1;
                                        state           <= CLR_D_CACHE_AND;
                                end

                                CASE_FLUSH_D_CACHE:
                                begin

                                        // Invalidate data cache.
                                        o_dcache_inv    <= 1'd1;
                                        state           <= CLR_D_CACHE;
                                end

                                CASE_FLUSH_I_CACHE:
                                begin

                                        // Invalidate instruction cache.
                                        o_icache_inv    <= 1'd1;
                                        state           <= CLR_I_CACHE;
                                end

                                CASE_CLEAN_ID_CACHE, CASE_CLEAN_D_CACHE:
                                begin
                                        // Clean D cache.
                                        o_dcache_clean <= 1'd1;
                                        state          <= CLEAN_D_CACHE;
                                end

                                CASE_CLFLUSH_D_CACHE:
                                begin
                                        // Clean D cache.
                                        o_dcache_clean <= 1'd1;
                                        state          <= CLFLUSH_D_CACHE;
                                end

                                CASE_CLFLUSH_ID_CACHE:
                                begin
                                        // Clean D cache.
                                        o_dcache_clean <= 1'd1;
                                        state          <= CLFLUSH_ID_CACHE;
                                end

                                default:
                                begin
                                        // Clean D cache.
                                        o_dcache_clean <= 1'd1;
                                        state          <= CLFLUSH_ID_CACHE;
                                end

                                endcase
                        end
                end

                ICACHE_PREFETCH: begin
                        o_icache_prefetch <= 1'b1;
                        if (i_icache_prefetch_done) begin o_icache_prefetch <= 1'b0;state <= DONE;end
                end
                DRAIN_WRITE_BUFFER: begin
                        if (wait_for_interrupt) begin
                                if (i_irq) o_wfi_irq <= 1'b1;
                                if (i_fiq) o_wfi_fiq <= 1'b1;
                        end
                        o_drain_write_buffer <= 1'b1;
                        if (i_write_buffer_empty) begin
                                o_drain_write_buffer <= 1'b0;
                                state <= wait_for_interrupt ? WAIT_FOR_INTERRUPT : DONE;
                        end
                end
                WAIT_FOR_INTERRUPT: begin
                        // IRQ/FIQ wake the core, including when masked; normal
                        // exception entry remains governed by the CPSR masks.
                        if (i_irq || i_fiq || o_wfi_irq || o_wfi_fiq) begin
                                o_wfi_irq <= o_wfi_irq || i_irq;
                                o_wfi_fiq <= o_wfi_fiq || i_fiq;
                                wait_for_interrupt <= 1'b0;state <= DONE;
                        end
                end
                LOCK_D_CACHE: begin
                        o_dcache_lock_write <= 1'b1;
                        if (i_dcache_lock_done) begin o_dcache_lock_write <= 1'b0;state <= DONE;end
                end
                LOCK_I_CACHE: begin
                        o_icache_lock_write <= 1'b1;
                        if (i_icache_lock_done) begin o_icache_lock_write <= 1'b0;state <= DONE;end
                end
                CLEAN_D_CACHE,
                CLFLUSH_ID_CACHE,
                CLFLUSH_D_CACHE:
                begin
                        o_dcache_clean <= 1'd1;

                        if ( i_dcache_clean_done )
                        begin
                                o_dcache_clean <= 1'd0;

                                if ( state == CLFLUSH_D_CACHE )
                                begin
                                        o_dcache_inv    <= 1'd1;
                                        state           <= CLR_D_CACHE;
                                end
                                else if ( state == CLFLUSH_ID_CACHE )
                                begin
                                        o_dcache_inv    <= 1'd1;
                                        state           <= CLR_D_CACHE_AND;
                                end
                                else // Clean D cache alone.
                                begin
                                        state <= DONE;
                                end
                        end
                end

                CLR_D_CACHE, CLR_D_CACHE_AND: // Clear data cache.
                begin
                        o_dcache_inv <= 1'd1;

                        // Wait for cache invalidation to complete.
                        if ( i_dcache_inv_done && state == CLR_D_CACHE )
                        begin
                                o_dcache_inv <= 1'd0;
                                state        <= DONE;
                        end
                        else if ( state == CLR_D_CACHE_AND && i_dcache_inv_done )
                        begin
                                o_dcache_inv <= 1'd0;
                                o_icache_inv <= 1'd1;
                                state        <= CLR_I_CACHE;
                        end
                end

                CLR_I_CACHE: // Clear instruction cache.
                begin
                        o_icache_inv <= 1'd1;

                        if ( i_icache_inv_done )
                        begin
                                o_icache_inv <= 1'd0;
                                state        <= DONE;
                        end
                end

                ACTIVE: // Access processor registers.
                begin
                        if ( is_cc_satisfied ( i_cp_word[31:28], i_cpsr[31:28] ) ||
                             i_cp_word ==? MRC2 ||
                             i_cp_word ==? MCR2 ||
                             i_cp_word ==? LDC2 ||
                             i_cp_word ==? STC2 )
                        begin
                                        if ( i_cp_word[20] ) // Load to CPU reg.
                                        begin
                                                // Register write command.
                                                o_reg_en        <= 1'd1;
                                                o_reg_wr_index  <= translate( {1'd0, i_cp_word[15:12]}, i_cpsr[ZAP_CPSR_MODE:0] );
                                                o_reg_wr_data   <= i_cp_word[19:16] == 0 && i_cp_word.ZAP_OPCODE_2 == 1 ?
                                                                   CACHE_TYPE_WORD :
                                                                   CP15_L4_DEFAULT && i_cp_word[19:16] == 9 && i_cp_word.ZAP_CRM == 0 && i_cp_word.ZAP_OPCODE_2 == 0 ?
                                                                   {o_dcache_lock_base,26'b0} :
                                                                   CP15_L4_DEFAULT && i_cp_word[19:16] == 9 && i_cp_word.ZAP_CRM == 0 && i_cp_word.ZAP_OPCODE_2 == 1 ?
                                                                   {o_icache_lock_base,26'b0} :
                                                                   i_cp_word[19:16] == 10 && i_cp_word.ZAP_CRM == 0 && i_cp_word.ZAP_OPCODE_2 == 0 ? i_dtlb_lock_read :
                                                                   i_cp_word[19:16] == 10 && i_cp_word.ZAP_CRM == 0 && i_cp_word.ZAP_OPCODE_2 == 1 ? i_itlb_lock_read : r[ i_cp_word[19:16] ];
                                                state           <= DONE;
                                        end
                                        else // Store from CPU register.
                                        begin
                                                // Generate CPU register read command. CP write.
                                                o_reg_en        <= 1'd1;
                                                o_reg_rd_index  <= translate({1'd0, i_cp_word[15:12]}, i_cpsr[ZAP_CPSR_MODE:0]);
                                                o_reg_wr_index  <= 16;
                                                state <= READ_DLY;
                                        end
                        end
                        else
                        begin
                                state <= DONE;
                        end
                end

                // ======================================
                // Default Section (For Better Synth)
                // ======================================

                default: // X propagate
                begin
                        state          <= 'x; //
                        o_dcache_inv   <= 'x; //
                        o_icache_inv   <= 'x; //
                        o_dcache_clean <= 'x; //
                        o_icache_clean <= 'x; //
                        o_dtlb_inv     <= 'x; //
                        o_itlb_inv     <= 'x; //
                        o_reg_en       <= 'x; //
                        o_cp_done      <= 'x; //
                        o_reg_wr_data  <= 'x; //
                        o_reg_wr_index <= 'x; //
                        o_reg_rd_index <= 'x; //

                        // Quartus 17 compat: replaced foreach with for loop
                        for (int i = 0; i < 14; i = i + 1)
                                r[i] <= 'x;
                end

                endcase

                // ======================================
                // Constants Section
                // ======================================

                // ARM920T ID fields; layout revision zero is a model choice,
                // not a measured identification from the physical phone.
                r[0][3:0]   <= 4'd0;
                r[0][15:4]  <= CP15_L4_DEFAULT ? 12'h920 : 12'hAAA;
                r[0][19:16] <= CP15_L4_DEFAULT ? 4'h2 : 4'h5;
                r[0][23:20] <= CP15_L4_DEFAULT ? 4'h1 : 4'h0;
                r[0][31:24] <= CP15_L4_DEFAULT ? 8'h41 : 8'h00;
                r[1][7]     <= BE_32_ENABLE ? 1'd1 : 1'd0;
                r[1][6:3]   <= 4'b1111;
                r[1][11:10] <= 2'b00; // ARM920 reserved: reads zero

                if ( ONLY_CORE )
                begin
                        r[1][2]  <= 1'd0;
                        r[1][12] <= 1'd0;
                        r[1][0]  <= 1'd0;
                end
        end
end

// For debugging.

logic [31:0] r0;
logic [31:0] r1;
logic [31:0] r2;
logic [31:0] r3;
logic [31:0] r4;
logic [31:0] r5;
logic [31:0] r6;

assign r0 = r[0];
assign r1 = r[1];
assign r2 = r[2];
assign r3 = r[3];
assign r4 = r[4];
assign r5 = r[5];
assign r6 = r[6];

logic unused;

assign unused = |{r0, r1, r2, r3, r4, r5, r6, i_cpsr[27:5],
                  i_icache_clean_done};

endmodule : zap_cp15_cb

// ============================================================================
// END OF FILE
// ============================================================================
