// Standalone CPU evaluation; this is not a Nokia SoC or the MiSTer top level.
module ngage_cpu_sim (
    input  logic          i_clk,
    input  logic          i_reset,
    input  logic          i_irq,
    input  logic          i_fiq,
    output logic          o_wb_cyc,
    output logic          o_wb_lock,
    output logic          o_wb_stb,
    output logic [31:0]   o_wb_adr,
    output logic          o_wb_we,
    output logic [31:0]   o_wb_dat,
    output logic [3:0]    o_wb_sel,
    output logic [2:0]    o_wb_cti,
    input  logic          i_wb_ack,
    input  logic [31:0]   i_wb_dat,
    input  logic          i_wb_err,
    output logic          o_wb_code,
    output logic [1023:0] o_trace,
    output logic          o_trace_valid,
    output logic          o_trace_uop_last,
    output logic          o_cp15_done,
    output logic [31:0]   o_cp15_word,
    output logic [31:0]   o_cp15_data,
    output logic          o_branch_valid,
    output logic [31:0]   o_branch_pc,
    output logic [31:0]   o_branch_target,
    output logic [31:0]   o_branch_prediction,
    output logic [1:0]    o_branch_state,
    output logic [1:0]    o_branch_redirect,
    output logic [31:0]   o_fetch_pc
);
    ngage_cpu cpu (
        .clk(i_clk), .reset(i_reset), .irq(i_irq), .fiq(i_fiq),
        .wb_lock(o_wb_lock), .wb_cyc(o_wb_cyc), .wb_stb(o_wb_stb),
        .wb_address(o_wb_adr), .wb_write(o_wb_we),
        .wb_write_data(o_wb_dat), .wb_byte_enable(o_wb_sel),
        .wb_cycle_type(o_wb_cti), .wb_burst_type(),
        .wb_ack(i_wb_ack), .wb_read_data(i_wb_dat), .wb_error(i_wb_err)
    );
    // Simulation-only observation of the decision before its active edge.
    assign o_branch_valid = cpu.u_zap.u_zap_core.u_zap_alu_main.branch_instruction &&
        cpu.u_zap.u_zap_core.u_zap_alu_main.o_dav_nxt &&
        !cpu.u_zap.u_zap_core.u_zap_alu_main.i_data_stall;
    assign o_branch_pc = cpu.u_zap.u_zap_core.u_zap_alu_main.i_pc_ff;
    assign o_branch_target = cpu.u_zap.u_zap_core.u_zap_alu_main.tmp_sum;
    assign o_branch_prediction = cpu.u_zap.u_zap_core.u_zap_alu_main.i_ppc_ff;
    assign o_branch_state = cpu.u_zap.u_zap_core.u_zap_alu_main.i_taken_ff;
    assign o_branch_redirect = cpu.u_zap.u_zap_core.u_zap_alu_main.w_clear_from_alu;
    assign o_fetch_pc = cpu.u_zap.u_zap_core.o_instr_wb_adr;
    assign o_trace = cpu.u_zap.o_trace;
    assign o_trace_valid = cpu.u_zap.o_trace_valid;
    assign o_trace_uop_last = cpu.u_zap.o_trace_uop_last;
    // Upstream's retirement text omits some coprocessor instructions. Keep
    // an explicit simulation-only view of completed CP15 transactions.
    assign o_cp15_done = cpu.u_zap.u_zap_core.copro_done;
    assign o_cp15_word = cpu.u_zap.u_zap_core.copro_word;
    assign o_wb_code = cpu.u_zap.l_merger_for_core_with_cache_mmu.u_zap_wb_merger.state_ff == 0;
    logic [31:0] cp15_write_data;
    // Sample MCR data in the same READ state/edge where CP15 consumes it.
    // The register-file read port is no longer guaranteed valid at DONE.
    always_ff @(posedge i_clk) begin
        if (i_reset) cp15_write_data <= 0;
        else if (cpu.u_zap.u_zap_core.u_zap_cp15_cb.state == 4'd3)
            cp15_write_data <= cpu.u_zap.u_zap_core.u_zap_cp15_cb.i_reg_rd_data;
    end
    assign o_cp15_data = o_cp15_word[20] ? cpu.u_zap.u_zap_core.copro_reg_wr_data
                                         : cp15_write_data;
endmodule
