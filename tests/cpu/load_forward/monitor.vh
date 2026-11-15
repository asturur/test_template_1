// Test-only check of the actual CPU completion/Memory seam.
integer load_forward_early = 0, load_forward_late = 0;
reg load_forward_pending = 0;
reg [31:0] load_forward_expected;
reg [5:0] load_forward_index;
always @(posedge clk) begin
  if (reset) begin
    load_forward_pending <= 0;
    load_forward_early <= 0;
    load_forward_late <= 0;
  end else begin
    if (load_forward_pending) begin
      if(!dut.u_zap.u_zap_core.memory_dav_ff || !dut.u_zap.u_zap_core.memory_mem_load_ff ||
      dut.u_zap.u_zap_core.memory_mem_srcdest_index_ff!=load_forward_index ||
      dut.u_zap.u_zap_core.memory_mem_rd_data!==load_forward_expected)
        $fatal(1, "early raw word differs from registered Memory formatter/owner");
    end
    load_forward_pending<=dut.u_zap.u_zap_core.issue_word_load_ready &&
                        !dut.u_zap.u_zap_core.clear_from_writeback;
    if (dut.u_zap.u_zap_core.issue_word_load_ready) begin
      if(dut.u_zap.u_zap_core.data_stall || !dut.u_zap.u_zap_core.completion_valid ||
      dut.u_zap.u_zap_core.completion_fault!=0 ||
      !dut.u_zap.u_zap_core.postalu_request_stb || !dut.u_zap.u_zap_core.postalu_request_cyc ||
      dut.u_zap.u_zap_core.postalu_address_ff[1:0]!=0 ||
      dut.u_zap.u_zap_core.postalu_swp_tag!=0 ||
      dut.u_zap.u_zap_core.postalu_ubyte_ff || dut.u_zap.u_zap_core.postalu_sbyte_ff ||
      dut.u_zap.u_zap_core.postalu_uhalf_ff || dut.u_zap.u_zap_core.postalu_shalf_ff)
        $fatal(1, "unowned/faulted/unformatted/SWP early load");
      load_forward_expected <= dut.u_zap.u_zap_core.completion_data;
      load_forward_index <= dut.u_zap.u_zap_core.postalu_mem_srcdest_index_ff;
      if (dut.u_zap.u_zap_core.u_zap_issue_main.operand_pop)
        load_forward_early <= load_forward_early + 1;
    end
    if(dut.u_zap.u_zap_core.u_zap_issue_main.memory_load_committing &&
     dut.u_zap.u_zap_core.u_zap_issue_main.operand_pop)
      load_forward_late <= load_forward_late + 1;
  end
end
