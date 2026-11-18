`define CORE dut.u_zap.u_zap_core
`define CACHE dut.u_zap.l_generate_with_cache_mmu.u_data_cache.cache_adapter
wire [31:0] watched_store_pc = (`CORE.data_select_p1 ?
    `CORE.postalu1_pc_plus_8_ff : `CORE.postalu_pc_plus_8_ff) - 8;
always @(posedge clk) begin
    if (!reset && `CORE.completion_offer && `CORE.o_data_wb_we &&
        (`CORE.o_data_wb_sel == 4'h3 || `CORE.o_data_wb_sel == 4'hc))
        $display("SAFE_HALF pc=%08h va=%08h mask=%h data=%08h accept=%0d credit=%0d ack=%0d",
            watched_store_pc, `CORE.o_data_alignment_far, `CORE.o_data_wb_sel, `CORE.o_data_wb_dat,
            `CACHE.cache.accept_demand, `CACHE.store_credit_accept, `CORE.i_data_wb_ack);
    if (!reset && ack && we && address == 32'h0a012000 && be == 4'hc)
        $display("SAFE_BUS va=%08h mask=%h data=%08h", address, be, wdata);
    if (!reset && `CORE.completion_valid && `CORE.completion_fault == 2'b01)
        $display("SAFE_FAULT pc=%08h far=%08h fsr=%02h", `CORE.postalu_pc_plus_8_ff-8,
            `CORE.completion_far, `CORE.completion_fsr);
end
`undef CACHE
`undef CORE
